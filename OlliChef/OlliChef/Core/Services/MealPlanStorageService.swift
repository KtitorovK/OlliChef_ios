import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Ported from mealPlanStorage.ts + firestoreService.ts's meal plan methods.
/// Path: users/{userId}/mealPlans/{mealPlanId}. Uses Codable's setData(from:), which
/// Firestore's encoder omits nil fields for — same "never write null" contract as the
/// RN app's removeUndefined, without hand-building a dictionary for every optional field.
enum MealPlanStorageService {
    private static var db: Firestore { Firestore.firestore() }

    private static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private static func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("mealPlans")
    }

    static func save(_ plan: MealPlan) async throws {
        guard let uid = currentUserId else {
            throw FirebaseTokenProviderError.signInRequired
        }
        let existing = try await collection(for: uid).document(plan.id).getDocument()
        var toWrite = plan
        toWrite.updatedAt = ISO8601DateFormatter().string(from: Date())
        if !existing.exists {
            toWrite.createdAt = toWrite.updatedAt
        }
        try collection(for: uid).document(plan.id).setData(from: toWrite)
    }

    static func get(_ mealPlanId: String) async throws -> MealPlan? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await collection(for: uid).document(mealPlanId).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: MealPlan.self)
    }

    /// Ported from firestoreService.ts's deleteMealPlan: hard-deletes the document.
    static func delete(_ mealPlanId: String) async throws {
        guard let uid = currentUserId else {
            throw FirebaseTokenProviderError.signInRequired
        }
        try await collection(for: uid).document(mealPlanId).delete()
    }

    private static func getAll() async throws -> [MealPlan] {
        guard let uid = currentUserId else { return [] }
        let snapshot = try await collection(for: uid).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: MealPlan.self) }
    }

    /// Ported from mealPlanStorage.ts's getMealPlans: prefers a plan covering today
    /// (latest startDate if several do), else the closest future plan, else nil —
    /// deliberately does not fall back to a past plan.
    static func currentMealPlan() async throws -> MealPlan? {
        let plans = try await getAll()
        guard !plans.isEmpty else { return nil }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        let validPlans = plans.filter { $0.startDate <= today && $0.endDate >= today }
        if let latest = validPlans.max(by: { $0.startDate < $1.startDate }) {
            return latest
        }

        let futurePlans = plans.filter { $0.startDate > today }
        if let earliest = futurePlans.min(by: { $0.startDate < $1.startDate }) {
            return earliest
        }

        return nil
    }
}
