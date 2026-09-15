import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Ported from userProfileService.ts. Writes are built as plain [String: Any]
/// dictionaries with nil fields omitted entirely — mirrors the RN app's
/// filterUndefinedValues/removeUndefined convention — rather than relying on
/// Codable's nil-encoding behavior, which doesn't guarantee the same "never write
/// null" contract.
enum UserProfileService {
    private static var db: Firestore { Firestore.firestore() }

    private static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    static func getUserProfile(userId: String? = nil) async throws -> UserProfile? {
        guard let uid = userId ?? currentUserId else { return nil }
        let snapshot = try await db.collection("userProfiles").document(uid).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: UserProfile.self)
    }

    static func createUserProfile(
        email: String,
        displayName: String?,
        privacyPolicyAccepted: Bool?,
        termsAccepted: Bool?
    ) async throws {
        guard let uid = currentUserId else { return }
        let now = ISO8601DateFormatter().string(from: Date())

        var data: [String: Any] = [
            "id": uid,
            "email": email,
            "createdAt": now,
            "updatedAt": now,
            "lastActive": now,
        ]
        if let displayName { data["displayName"] = displayName }
        if let privacyPolicyAccepted { data["privacyPolicyAccepted"] = privacyPolicyAccepted }
        if let termsAccepted { data["termsAccepted"] = termsAccepted }

        try await db.collection("userProfiles").document(uid).setData(data)
    }

    /// Mirrors initializeProfile: only creates a profile if one doesn't already exist.
    static func initializeProfile(
        email: String,
        displayName: String?,
        privacyPolicyAccepted: Bool? = nil,
        termsAccepted: Bool? = nil
    ) async throws {
        if try await getUserProfile() != nil { return }
        try await createUserProfile(
            email: email,
            displayName: displayName,
            privacyPolicyAccepted: privacyPolicyAccepted,
            termsAccepted: termsAccepted
        )
    }

    static func updateLastActive() async throws {
        guard let uid = currentUserId else { return }
        try await db.collection("userProfiles").document(uid).updateData([
            "lastActive": ISO8601DateFormatter().string(from: Date()),
        ])
    }

    /// Mirrors updateUserProfile: a merge-write so a missing profile doc doesn't throw.
    static func updateDisplayName(_ displayName: String) async throws {
        guard let uid = currentUserId else { return }
        try await db.collection("userProfiles").document(uid).setData([
            "displayName": displayName,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ], merge: true)
    }

    /// Mirrors deleteUserAccount: anonymizes the user's data (preserved for analytics,
    /// stripped of the live user association), deletes the profile doc, then deletes
    /// the Firebase Auth user itself. No re-authentication step — matches RN exactly,
    /// which also has none; a `requires-recent-login` failure just surfaces as a plain
    /// "failed to delete" error to the caller, same as here.
    static func deleteAccount() async throws {
        guard let uid = currentUserId, let currentUser = Auth.auth().currentUser else { return }

        try await anonymizeUserData(uid)
        try await db.collection("userProfiles").document(uid).delete()
        try await currentUser.delete()
    }

    /// Mirrors anonymizeUserData: moves each doc in mealPlans/groceryLists/
    /// chatConversations to a top-level anonymized collection (tagged with
    /// originalUserId + anonymizedAt), deletes the original, then deletes the
    /// now-empty users/{uid} doc itself.
    private static func anonymizeUserData(_ uid: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let userDoc = db.collection("users").document(uid)

        for (subcollection, anonymizedCollection) in [
            ("mealPlans", "anonymizedMealPlans"),
            ("groceryLists", "anonymizedGroceryLists"),
            ("chatConversations", "anonymizedChatConversations"),
        ] {
            let snapshot = try await userDoc.collection(subcollection).getDocuments()
            for document in snapshot.documents {
                var anonymizedData = document.data()
                anonymizedData["originalUserId"] = uid
                anonymizedData["anonymizedAt"] = now
                try await db.collection(anonymizedCollection).document(document.documentID).setData(anonymizedData)
                try await document.reference.delete()
            }
        }

        try await userDoc.delete()
    }
}
