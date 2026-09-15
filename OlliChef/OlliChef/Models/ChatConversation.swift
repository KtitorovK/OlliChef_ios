import Foundation

/// Ported from src/types/chat.ts's ChatConversation. `openaiConversationId` replaces
/// the original `openaiThreadId` — OpenAI's Assistants API (threads) was shut down
/// 2026-08-26; its replacement is the Conversations API. No data migration: nothing
/// is live on PROD yet, so old field values (if any exist) are simply dead.
struct ChatConversation: Codable {
    var id: String
    var userId: String
    var title: String?
    var openaiConversationId: String?
    var createdAt: String
    var updatedAt: String
    var lastMessageAt: String?
    var messageCount: Int
    var isArchived: Bool?
}
