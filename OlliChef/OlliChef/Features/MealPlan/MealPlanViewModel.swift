import Combine
import Foundation

@MainActor
final class MealPlanViewModel: ObservableObject {
    @Published var mealPlan: MealPlan?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isClearing = false
    @Published var clearError: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            mealPlan = try await MealPlanStorageService.currentMealPlan()
            // Mirrors loadMealPlan's fire-and-forget preload: warms the Pexels cache for
            // every meal in the plan so MealImageView rarely shows its loading spinner.
            if let allMeals = mealPlan?.days.flatMap(\.meals), !allMeals.isEmpty {
                Task { await PexelsService.shared.preloadImages(allMeals) }
            }
        } catch {
            handleError(error, context: ErrorContext(location: "MealPlanScreen", action: "load"))
            errorMessage = NetworkErrorClassifier.isNetworkError(error) ? NetworkConfig.offlineMessage : "Failed to load meal plan"
        }
    }

    /// Mirrors MealPlanScreen.tsx's "Clear Current Meal Plan" action: deletes the plan
    /// and its grocery list, then reloads to show the empty state. RN also cancels any
    /// in-flight AI generation tied to the plan id first — this app's chat generation is
    /// a single blocking request/response with no equivalent tracked generation state to
    /// cancel, so that step has nothing to port to.
    func clearMealPlan(router: TabRouter) async {
        guard let mealPlan else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            try await MealPlanStorageService.delete(mealPlan.id)
            try await GroceryListStorageService.deleteByMealPlanId(mealPlan.id)
            await load()
            router.mealPlanClearedAt = Date()
        } catch {
            handleError(error, context: ErrorContext(location: "MealPlanScreen", action: "clearMealPlan"))
            clearError = "Failed to clear meal plan"
        }
    }
}
