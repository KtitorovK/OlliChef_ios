import Combine
import SwiftUI

enum MainTab: Hashable, CaseIterable, Identifiable {
    case chat, mealPlan, groceries

    var id: Self { self }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .mealPlan: return "Meal Plan"
        case .groceries: return "Groceries"
        }
    }

    var iconName: String {
        switch self {
        case .chat: return "IconChat"
        case .mealPlan: return "IconMealPlan"
        case .groceries: return "IconGroceries"
        }
    }
}

/// Lets any tab's content switch the selected tab — used after accepting a meal plan,
/// mirroring the RN app's navigation.navigate('MealPlan').
final class TabRouter: ObservableObject {
    @Published var selection: MainTab = .chat
    /// Bumped by UserProfileViewModel.clearChatHistory() so the already-mounted
    /// ChatScreen (kept alive across tab switches on both iPhone and iPad) knows to
    /// drop its in-memory messages and reload — without this, clearing history only
    /// reset the server-side conversation, and the old messages kept showing until
    /// the next full app relaunch recreated ChatViewModel from scratch.
    @Published var chatHistoryClearedAt: Date?
    /// Same reasoning as chatHistoryClearedAt: GroceryListScreen also stays mounted
    /// across tab switches, so clearing the meal plan (which deletes its grocery list
    /// too) needs an explicit signal — otherwise Groceries keeps showing the
    /// now-deleted items until the user happens to pull-to-refresh.
    @Published var mealPlanClearedAt: Date?
    /// Set by the platform-specific "Clear Current Meal Plan" toolbar button (declared
    /// outside MealPlanScreen — see its own comment for why) once the user confirms;
    /// MealPlanScreen observes this and performs the actual clear.
    @Published var requestMealPlanClear: Date?
    /// Kept in sync by MealPlanScreen so the outer "Clear Current Meal Plan" button
    /// (see requestMealPlanClear) knows whether there's anything to clear, without
    /// reaching into MealPlanScreen's own privately-owned view model.
    @Published var hasMealPlan = false
    /// Kept in sync by GroceryListScreen whenever its items change (load, toggle).
    /// nil means there's nothing to share yet. The outer "Share" toolbar button
    /// (declared outside GroceryListScreen — see its own comment for why) reads this
    /// instead of reaching into GroceryListScreen's own privately-owned view model.
    @Published var groceryShareText: String?
}
