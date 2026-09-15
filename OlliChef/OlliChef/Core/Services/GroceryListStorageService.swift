import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Ported from firestoreService.ts's grocery list methods.
/// Path: users/{userId}/groceryLists/{groceryListId} — one document per meal plan,
/// looked up by its `mealPlanId` field rather than by document id.
enum GroceryListStorageService {
    private static var db: Firestore { Firestore.firestore() }

    private static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private static func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("groceryLists")
    }

    static func create(_ list: GroceryList) async throws {
        guard let uid = currentUserId else {
            throw FirebaseTokenProviderError.signInRequired
        }
        try collection(for: uid).document(list.id).setData(from: list)
    }

    static func get(byMealPlanId mealPlanId: String) async throws -> GroceryList? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await collection(for: uid)
            .whereField("mealPlanId", isEqualTo: mealPlanId)
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: GroceryList.self) }
    }

    static func update(_ list: GroceryList) async throws {
        guard let uid = currentUserId else {
            throw FirebaseTokenProviderError.signInRequired
        }
        var toWrite = list
        toWrite.updatedAt = ISO8601DateFormatter().string(from: Date())
        try collection(for: uid).document(list.id).setData(from: toWrite)
    }

    /// Mirrors deleteGroceryListByMealPlanId: batch-deletes every list linked to a
    /// meal plan (in practice there's ever only one) before a fresh one is created.
    static func deleteByMealPlanId(_ mealPlanId: String) async throws {
        guard let uid = currentUserId else { return }
        let snapshot = try await collection(for: uid)
            .whereField("mealPlanId", isEqualTo: mealPlanId)
            .getDocuments()
        guard !snapshot.documents.isEmpty else { return }

        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        try await batch.commit()
    }
}
