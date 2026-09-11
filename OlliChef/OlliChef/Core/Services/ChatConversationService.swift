import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Ported from firestoreService.ts's chat conversation methods.
/// Path: users/{userId}/chatConversations/{conversationId} — matches COLLECTIONS
/// in config/firebase.ts exactly.
enum ChatConversationService {
    private static var db: Firestore { Firestore.firestore() }

    private static func collection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("chatConversations")
    }

    private static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    static func create(openaiThreadId: String, title: String = "New Chat") async throws -> ChatConversation {
        guard let uid = currentUserId else {
            throw FirebaseTokenProviderError.signInRequired
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let docRef = collection(for: uid).document()
        let conversation = ChatConversation(
            id: docRef.documentID,
            userId: uid,
            title: title,
            openaiThreadId: openaiThreadId,
            createdAt: now,
            updatedAt: now,
            lastMessageAt: nil,
            messageCount: 0,
            isArchived: nil
        )
        try docRef.setData(from: conversation)
        return conversation
    }

    static func get(_ conversationId: String) async throws -> ChatConversation? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await collection(for: uid).document(conversationId).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: ChatConversation.self)
    }

    static func mostRecent() async throws -> ChatConversation? {
        guard let uid = currentUserId else { return nil }
        let snapshot = try await collection(for: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first?.data(as: ChatConversation.self)
    }

    static func update(_ conversationId: String, openaiThreadId: String? = nil, lastMessageAt: String? = nil, messageCount: Int? = nil) async throws {
        guard let uid = currentUserId else { return }
        var data: [String: Any] = ["updatedAt": ISO8601DateFormatter().string(from: Date())]
        if let openaiThreadId { data["openaiThreadId"] = openaiThreadId }
        if let lastMessageAt { data["lastMessageAt"] = lastMessageAt }
        if let messageCount { data["messageCount"] = messageCount }
        try await collection(for: uid).document(conversationId).updateData(data)
    }
}
