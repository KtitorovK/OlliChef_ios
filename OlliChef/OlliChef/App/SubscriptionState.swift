import Combine
import Foundation

/// Ported from SubscriptionContext.tsx, minus the Android/password-user "plug" bypass
/// (permanent fake access) — not applicable here since this app is Sign in with Apple
/// only, iOS only. StoreKit is the source of truth; Firestore sync is a dedup'd
/// side effect, never read back for access decisions.
@MainActor
final class SubscriptionState: ObservableObject {
    @Published private(set) var status: SubscriptionStatusInfo?
    @Published private(set) var hasAccess = false
    @Published private(set) var isLoading = true

    /// 10s — matches GET_STATUS_TIMEOUT_MS exactly. StoreKit's currentEntitlements +
    /// Product.products both hit the network on cold start; too short a timeout was a
    /// real incident in the RN app (active trial users landing on the paywall).
    private static let getStatusTimeoutNanoseconds: UInt64 = 10_000_000_000

    private var lastSyncedStatusKey: String?
    private var refreshInFlight = false
    private var lastRefreshRequestTime: Date?
    private var listenerStarted = false

    /// Call when the signed-in user changes (including sign-out, with nil).
    func start(for userId: String?) async {
        guard userId != nil else {
            status = nil
            hasAccess = false
            isLoading = false
            lastSyncedStatusKey = nil
            return
        }

        lastSyncedStatusKey = nil

        if !listenerStarted {
            listenerStarted = true
            await StoreKitService.shared.startListening { [weak self] newStatus in
                Task { @MainActor in
                    guard let self else { return }
                    self.status = newStatus
                    self.hasAccess = newStatus.hasAccess
                    await self.syncToFirestoreIfChanged(newStatus)
                }
            }
        }

        isLoading = true
        status = nil
        await checkEntitlement(silent: false)
    }

    /// Mirrors the AppState 'active' listener: a silent re-check on foreground, only
    /// once entitlement has actually been checked at least once.
    func handleAppForeground() async {
        guard status != nil else { return }
        await checkEntitlement(silent: true)
    }

    /// Mirrors refreshSubscription: debounced (3s) and in-flight guarded, used by the
    /// paywall right after a purchase or restore.
    @discardableResult
    func refresh() async -> Bool {
        guard !refreshInFlight else { return hasAccess }
        if let lastRefreshRequestTime, Date().timeIntervalSince(lastRefreshRequestTime) < 3 {
            return hasAccess
        }
        lastRefreshRequestTime = Date()
        refreshInFlight = true
        defer { refreshInFlight = false }
        let result = await checkEntitlement(silent: true)
        return result.hasAccess
    }

    @discardableResult
    private func checkEntitlement(silent: Bool) async -> SubscriptionStatusInfo {
        defer { if !silent { isLoading = false } }

        let resolved = await withTimeoutOrNil(Self.getStatusTimeoutNanoseconds) {
            await StoreKitService.shared.getStatus()
        } ?? SubscriptionStatusInfo() // timed out — treat as inactive, matching the RN catch block

        status = resolved
        hasAccess = resolved.hasAccess
        await syncToFirestoreIfChanged(resolved)
        return resolved
    }

    private func syncToFirestoreIfChanged(_ status: SubscriptionStatusInfo) async {
        let key = status.statusKey
        guard key != lastSyncedStatusKey else { return }
        lastSyncedStatusKey = key
        do {
            try await SubscriptionStorageService.updateSubscriptionStatus(status)
        } catch {
            handleError(error, context: ErrorContext(location: "SubscriptionState", action: "syncToFirestore"))
        }
    }
}

/// A generic async timeout: returns nil if `operation` doesn't finish within
/// `nanoseconds`, matching withTimeout.ts's role for getStatus() specifically.
private func withTimeoutOrNil<T: Sendable>(
    _ nanoseconds: UInt64,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: nanoseconds)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
