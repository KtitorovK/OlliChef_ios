import Combine
import Foundation

@MainActor
final class RecipeStoryViewModel: ObservableObject {
    @Published var story: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(for meal: Meal) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            story = try await RecipeService.shared.getRecipeStory(for: meal)
        } catch {
            handleError(error, context: ErrorContext(location: "RecipeStoryScreen", action: "load"))
            errorMessage = NetworkErrorClassifier.isNetworkError(error) ? NetworkConfig.offlineMessage : "Couldn't load this recipe. Please try again."
        }
    }
}
