import Combine
import Foundation

@MainActor
final class MealPlanViewModel: ObservableObject {
    @Published var mealPlan: MealPlan?
    @Published var isLoading = false
    @Published var errorMessage: String?

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
}
