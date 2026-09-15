import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Ported from subscriptionService.ts's updateSubscriptionStatus. Write-only: StoreKit
/// is the source of truth for entitlement on iOS, this merge-write exists purely for
/// app/backend visibility — nothing reads it back for access decisions, matching the
/// RN app exactly (no Firestore listeners for subscription state).
enum SubscriptionStorageService {
    private static var db: Firestore { Firestore.firestore() }

    private static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    static func updateSubscriptionStatus(_ status: SubscriptionStatusInfo) async throws {
        guard let uid = currentUserId else { return }

        let displayStatus: String
        if status.state == .grace {
            displayStatus = "grace"
        } else if status.state == .active && status.isTrial {
            displayStatus = "trial"
        } else if status.state == .active {
            displayStatus = "active"
        } else {
            displayStatus = "inactive"
        }

        let now = ISO8601DateFormatter().string(from: Date())
        var subscription: [String: Any] = [
            "plan": "basic",
            "platform": "ios",
            "status": displayStatus,
            "isTrial": status.isTrial,
            "willAutoRenew": status.willAutoRenew,
            "lastCheckedAt": now,
        ]
        if let productId = status.productId { subscription["productId"] = productId }
        if let expiresAt = status.expiresAt {
            subscription["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
        }
        if let gracePeriodExpiresAt = status.gracePeriodExpiresAt {
            subscription["gracePeriodExpiresAt"] = ISO8601DateFormatter().string(from: gracePeriodExpiresAt)
        }

        try await db.collection("userProfiles").document(uid).setData([
            "subscription": subscription,
            "updatedAt": now,
        ], merge: true)
    }
}
