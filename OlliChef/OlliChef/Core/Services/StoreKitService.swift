import StoreKit
import UIKit

/// Adapted directly from the RN app's own StoreKitBridge.swift — already pure
/// StoreKit 2 (no SKPaymentQueue), just stripped of its RCTEventEmitter/Objective-C
/// bridging since there's no JS side to bridge to anymore. Logic (entitlement scan,
/// grace period, verification) is unchanged from the proven original.
struct SubscriptionStatusInfo: Equatable {
    enum State: String {
        case inactive, active, grace
    }

    var state: State = .inactive
    var productId: String?
    var expiresAt: Date?
    var isTrial: Bool = false
    var willAutoRenew: Bool = false
    var gracePeriodExpiresAt: Date?

    /// Mirrors SubscriptionContext.tsx's statusKey — used to dedupe Firestore writes.
    var statusKey: String {
        "\(state.rawValue)|\(productId ?? "")|\(expiresAt?.timeIntervalSince1970 ?? 0)"
    }

    /// Mirrors storekit.ts's hasPremium (iOS branch only — the native app has no
    /// Android/password-user "plug" bypass to replicate).
    var hasAccess: Bool {
        switch state {
        case .grace:
            guard let gracePeriodExpiresAt else { return true }
            return gracePeriodExpiresAt > Date()
        case .active:
            guard let expiresAt else { return false }
            return expiresAt > Date()
        case .inactive:
            return false
        }
    }
}

struct SubscriptionProductInfo {
    let id: String
    let displayName: String
    let displayPrice: String
    let isEligibleForIntroOffer: Bool
}

enum StoreKitServiceError: Error {
    case productNotFound
}

actor StoreKitService {
    static let shared = StoreKitService()
    static let productID = "com.biteplanai.basic"

    private var updatesTask: Task<Void, Never>?
    private var onUpdate: (@Sendable (SubscriptionStatusInfo) -> Void)?

    private init() {}

    /// Mirrors startTransactionObserver: listens for renewals/cancels/refunds for the
    /// lifetime of the app, notifying `onUpdate` whenever a verified auto-renewable
    /// transaction updates.
    func startListening(onUpdate: @escaping @Sendable (SubscriptionStatusInfo) -> Void) {
        self.onUpdate = onUpdate
        guard updatesTask == nil else { return }
        updatesTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result, transaction.productType == .autoRenewable {
                    await transaction.finish()
                    let status = await Self.readStatus()
                    await self.notify(status)
                }
            }
        }
    }

    private func notify(_ status: SubscriptionStatusInfo) {
        onUpdate?(status)
    }

    func fetchProduct() async throws -> SubscriptionProductInfo {
        guard let product = try await Product.products(for: [Self.productID]).first else {
            throw StoreKitServiceError.productNotFound
        }
        let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
        return SubscriptionProductInfo(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            isEligibleForIntroOffer: eligible
        )
    }

    enum PurchaseOutcome {
        case success, cancelled, pending
    }

    func purchase() async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [Self.productID]).first else {
            throw StoreKitServiceError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await transaction.finish()
            let status = await Self.readStatus()
            notify(status)
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws -> SubscriptionStatusInfo {
        try await AppStore.sync()
        let status = await Self.readStatus()
        notify(status)
        return status
    }

    func showManageSubscriptions() async throws {
        guard let scene = await UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        try await AppStore.showManageSubscriptions(in: scene)
    }

    func getStatus() async -> SubscriptionStatusInfo {
        await Self.readStatus()
    }

    /// Mirrors readStatus: scans current entitlements for the latest-expiry
    /// auto-renewable transaction, then cross-references RenewalInfo (a separate
    /// StoreKit type from Transaction) for willAutoRenew and grace period.
    static func readStatus() async -> SubscriptionStatusInfo {
        var best: Transaction?
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productType == .autoRenewable {
                if best == nil || (t.expirationDate ?? .distantPast) > (best?.expirationDate ?? .distantPast) {
                    best = t
                }
            }
        }

        guard let t = best else { return SubscriptionStatusInfo() }

        let isRevoked = t.revocationDate != nil
        let isExpired = t.expirationDate.map { $0 <= Date() } ?? true
        let isActive = !isRevoked && !isExpired
        let isTrial = t.offerType == .introductory

        var willAutoRenew = false
        var gracePeriodExpiresAt: Date?
        var state: SubscriptionStatusInfo.State = isActive ? .active : .inactive

        if let products = try? await Product.products(for: [t.productID]),
           let product = products.first,
           let subStatuses = try? await product.subscription?.status {
            for subStatus in subStatuses {
                if case .verified(let renewalInfo) = subStatus.renewalInfo {
                    willAutoRenew = renewalInfo.willAutoRenew
                    gracePeriodExpiresAt = renewalInfo.gracePeriodExpirationDate
                }
                if subStatus.state == .inGracePeriod {
                    state = .grace
                } else if subStatus.state == .inBillingRetryPeriod {
                    state = .inactive
                }
            }
        }

        return SubscriptionStatusInfo(
            state: state,
            productId: t.productID,
            expiresAt: t.expirationDate,
            isTrial: isTrial,
            willAutoRenew: willAutoRenew,
            gracePeriodExpiresAt: gracePeriodExpiresAt
        )
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }
}
