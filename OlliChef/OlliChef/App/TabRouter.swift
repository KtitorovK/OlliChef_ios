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
}
