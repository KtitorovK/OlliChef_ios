import Foundation

/// Ported from src/types/user.ts. Only the fields actually written during sign-in
/// (id, email, displayName, timestamps, acceptances) are populated here — preferences
/// and subscription fields exist on the Firestore contract but are set by later phases.
struct UserProfile: Codable {
    var id: String
    var email: String
    var displayName: String?
    var photoURL: String?
    var dietaryPreferences: [String]?
    var allergies: [String]?
    var cookingSkillLevel: String?
    var createdAt: String
    var updatedAt: String
    var lastActive: String
    var privacyPolicyAccepted: Bool?
    var termsAccepted: Bool?
}
