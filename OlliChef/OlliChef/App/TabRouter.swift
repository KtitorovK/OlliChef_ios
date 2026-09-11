import Combine
import SwiftUI

enum MainTab: Hashable {
    case chat, mealPlan, groceries
}

/// Lets any tab's content switch the selected tab — used after accepting a meal plan,
/// mirroring the RN app's navigation.navigate('MealPlan').
final class TabRouter: ObservableObject {
    @Published var selection: MainTab = .chat
}
