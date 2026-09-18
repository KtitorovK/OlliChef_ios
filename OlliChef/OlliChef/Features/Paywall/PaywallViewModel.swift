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

    // Wording locked by the founder-approved paywall copy (KB §3, Subscription &
    // Monetisation) for the trial-eligible case; the non-eligible branch isn't part
    // of that copy (it covers a returning subscriber, not the first-run paywall) so
    // it stays close to the same voice instead of inventing something new.
    var subscribeLabel: String {
        if isEligibleForTrial == true {
            return "Start my free 14-day trial"
        } else if let priceText {
            return "Subscribe for \(priceText)/month"
        }
        return "Subscribe"
    }

    /// Billing terms shown directly under the CTA — Apple treats a trial CTA that
    /// hides the eventual charge as a dark pattern, so this can't just live in a
    /// deemphasized line above the button the way `priceHint` used to.
    var legalFootnote: String? {
        guard let priceText else { return nil }
        if isEligibleForTrial == true {
            return "\(priceText)/month after free trial. Cancel anytime in App Store settings. Payment charged at trial end."
        }
        return "\(priceText)/month, auto-renewing. Cancel anytime in App Store settings."
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
