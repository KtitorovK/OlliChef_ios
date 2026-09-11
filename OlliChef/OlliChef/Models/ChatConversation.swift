import Foundation

/// Ported from src/types/chat.ts's ChatConversation.
struct ChatConversation: Codable {
    var id: String
    var userId: String
    var title: String?
    var openaiThreadId: String?
    var createdAt: String
    var updatedAt: String
    var lastMessageAt: String?
    var messageCount: Int
    var isArchived: Bool?
}
