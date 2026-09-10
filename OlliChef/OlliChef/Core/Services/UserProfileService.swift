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
}
