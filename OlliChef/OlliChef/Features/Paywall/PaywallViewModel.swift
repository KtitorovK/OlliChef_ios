import Combine
import Foundation

@MainActor
final class PaywallViewModel: ObservableObject {
    @Published var isEligibleForTrial: Bool?
    @Published var priceText: String?
    @Published var isPurchasing = false
    @Published var isRestoring = false
    @Published var alert: (title: String, message: String)?

    var isLoading: Bool { isEligibleForTrial == nil }

    /// True once `isEligibleForTrial` resolves to false — i.e. this Apple ID has
    /// used the trial for this subscription before. That's the only reliable signal
    /// StoreKit gives us for "returning subscriber" without the added work of a
    /// Win-Back Offers setup, so it's what drives both the "Expired" label and the
    /// button wording below.
    var isReturningSubscriber: Bool { isEligibleForTrial == false }

    // Wording locked by the founder-approved paywall copy (KB §3, Subscription &
    // Monetisation) for the trial-eligible case; the returning-subscriber branch
    // isn't part of that copy (it covers someone whose access already lapsed, not
    // the first-run paywall) so it stays close to the same voice instead of
    // inventing something new.
    var subscribeLabel: String {
        if isEligibleForTrial == true {
            return "Start my free 14-day trial"
        } else if let priceText {
            return "Buy for \(priceText)/month"
        }
        return "Subscribe"
    }

    /// Billing terms shown directly under the CTA — Apple treats a trial CTA that
    /// hides the eventual charge as a dark pattern, so this can't just live in a
    /// deemphasized line above the button the way `priceHint` used to. The renewal
    /// sentence is the long-standing standard auto-renewable-subscription disclosure
    /// (Apple Developer Program License Agreement, Schedule 2) — stating a cancel-by
    /// window, not just "cancel anytime", is the actual substance that requirement is
    /// after.
    var legalFootnote: String? {
        guard let priceText else { return nil }
        let renewalDisclosure = "Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in App Store settings."
        if isEligibleForTrial == true {
            return "\(priceText)/month after free trial. \(renewalDisclosure)"
        }
        return "\(priceText)/month. \(renewalDisclosure)"
    }

    /// Mirrors the effect in PaywallScreen.tsx. RN also calls getStatus() first to
    /// compute `eligibleByStatus = status.status !== 'expired'` — skipped here because
    /// the native StoreKitService's readStatus() only ever produces inactive/active/
    /// grace, never "expired", so that check is always true and contributes nothing.
    func load() async {
        do {
            let product = try await StoreKitService.shared.fetchProduct()
            isEligibleForTrial = product.isEligibleForIntroOffer
            priceText = product.displayPrice
        } catch {
            // Can't determine status — safe default: show trial, matching RN's catch.
            isEligibleForTrial = true
        }
    }

    func subscribe(subscriptionState: SubscriptionState) async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let outcome = try await StoreKitService.shared.purchase()
            switch outcome {
            case .success:
                await subscriptionState.refresh()
            case .cancelled:
                break
            case .pending:
                alert = ("Pending", "Your purchase is being processed. Please wait a moment.")
            }
        } catch {
            handleError(error, context: ErrorContext(location: "PaywallScreen", action: "subscribe"))
            alert = ("Error", "Purchase failed. Please try again.")
        }
    }

    func restore(subscriptionState: SubscriptionState) async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            _ = try await StoreKitService.shared.restore()
            let hasAccess = await subscriptionState.refresh()
            if !hasAccess {
                alert = ("No Active Subscription", "No active subscription was found.")
            }
        } catch {
            handleError(error, context: ErrorContext(location: "PaywallScreen", action: "restore"))
            alert = ("Restore Failed", "Unable to restore purchases. Please try again.")
        }
    }
}
