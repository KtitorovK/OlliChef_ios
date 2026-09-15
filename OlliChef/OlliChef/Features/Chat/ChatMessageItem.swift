import Foundation

/// Ported from ChatScreen.tsx's Message interface.
struct ChatMessageItem: Identifiable {
    let id: String
    let role: Role
    var content: String?
    let timestamp: Date
    var error: String?
    var mealPlan: MealPlan?

    enum Role: String {
        case user, assistant
    }
}
