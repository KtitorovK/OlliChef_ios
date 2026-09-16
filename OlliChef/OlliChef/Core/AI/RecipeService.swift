import Foundation

/// Ported from recipeService.ts: a plain, stateless Chat Completions call (not part of
/// ChatService's conversation) that returns a Markdown recipe story, backed by a
/// dual-layer cache — in-memory for instant re-access within a session, plus
/// UserDefaults (the native equivalent of AsyncStorage) so it survives relaunches.
actor RecipeService {
    static let shared = RecipeService()

    private static let cachePrefix = "recipe_story_"
    private static let expirationSeconds: TimeInterval = 24 * 60 * 60

    private let client = APIClient(serviceName: "RecipeService")
    private var memoryCache: [String: (story: String, timestamp: Date)] = [:]

    private init() {}

    private struct ChatCompletionResult: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]?
    }

    private static func cacheKey(for mealName: String) -> String {
        let sanitized = mealName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return cachePrefix + String(sanitized)
    }

    private static func isCacheValid(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) < expirationSeconds
    }

    private func cachedStory(for mealName: String) -> String? {
        if let entry = memoryCache[mealName], Self.isCacheValid(entry.timestamp) {
            return entry.story
        }

        let key = Self.cacheKey(for: mealName)
        guard let cached = UserDefaults.standard.dictionary(forKey: key),
              let story = cached["story"] as? String,
              let timestamp = cached["timestamp"] as? Double else {
            return nil
        }
        let date = Date(timeIntervalSince1970: timestamp)
        guard Self.isCacheValid(date) else { return nil }

        memoryCache[mealName] = (story, date)
        return story
    }

    private func saveStoryToCache(_ story: String, for mealName: String) {
        let now = Date()
        memoryCache[mealName] = (story, now)
        let key = Self.cacheKey(for: mealName)
        UserDefaults.standard.set(["story": story, "timestamp": now.timeIntervalSince1970], forKey: key)
    }

    /// Mirrors createStoryPrompt, extended with real quantities (not just names) so the
    /// AI's instructions reference the same amounts already shown to the user from the
    /// meal plan, instead of inventing its own — and told not to repeat the list, since
    /// RecipeStoryScreen already renders it separately from `meal.ingredients` directly.
    private static func storyPrompt(for meal: Meal) -> String {
        let ingredients = meal.ingredients.map(\.displayLabel).joined(separator: ", ")
        return "Meal: \(meal.name)\nIngredients: \(ingredients)\n\nThe ingredient list above is already shown to the user separately — do not include your own ingredients list, and use these exact quantities in your instructions. Please format the recipe using Markdown, with each step title as a level 3 heading (###)."
    }

    /// Mirrors getRecipeStory: cache first, else a fresh AI call, cached before returning.
    func getRecipeStory(for meal: Meal) async throws -> String {
        if let cached = cachedStory(for: meal.name) {
            return cached
        }

        let systemPrompt = await PromptManager.shared.recipePrompt()
        let model = await PromptManager.shared.aiModel()

        var request = URLRequest(url: URL(string: "\(Secrets.firebaseOpenAIProxyURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": Self.storyPrompt(for: meal)],
            ],
            "max_completion_tokens": 800,
            "stream": false,
        ])

        let (data, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(request)
        }

        let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
        let story = result.choices?.first?.message.content ?? ""
        guard !story.isEmpty else {
            throw ChatServiceError.noAssistantMessage
        }

        saveStoryToCache(story, for: meal.name)
        return story
    }
}
