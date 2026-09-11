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
        } catch {
            handleError(error, context: ErrorContext(location: "MealPlanScreen", action: "load"))
            errorMessage = NetworkErrorClassifier.isNetworkError(error) ? NetworkConfig.offlineMessage : "Failed to load meal plan"
        }
    }
}
