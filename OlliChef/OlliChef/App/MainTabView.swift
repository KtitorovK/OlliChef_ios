import SwiftUI

/// Mirrors AppNavigator.tsx's TabNavigator: three tabs (Chat, MealPlan, GroceryList),
/// no header of its own — the shared header (logo + profile) belongs to the enclosing
/// stack, matching the RN app's headerShown:false-at-the-tab-level structure.
/// NavigationSplitView adoption for iPad is its own later phase — this is a plain
/// adaptive TabView for now, per the Foundation phase's scope.
struct MainTabView: View {
    @StateObject private var router = TabRouter()

    var body: some View {
        TabView(selection: $router.selection) {
            ChatScreen()
                .tabItem { Label("Chat", image: "IconChat") }
                .tag(MainTab.chat)

            MealPlanScreen()
                .tabItem { Label("Meal Plan", image: "IconMealPlan") }
                .tag(MainTab.mealPlan)

            GroceryListScreen()
                .tabItem { Label("Groceries", image: "IconGroceries") }
                .tag(MainTab.groceries)
        }
        .tint(AppColor.brandPrimary)
        .environmentObject(router)
    }
}
