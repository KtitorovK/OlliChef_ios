import Foundation

/// Ported from pexelsService.ts: a food photo lookup by meal name, backed by a
/// TTL-less URL cache (not the image bytes) keyed by meal name — the same simple
/// persistence style as RecipeService's cache, just without an expiry, matching the
/// RN imageCacheService exactly (a cached URL never expires there either).
actor PexelsService {
    static let shared = PexelsService()

    private static let baseURL = "https://api.pexels.com/v1"
    private static let cachePrefix = "image_cache_"

    /// Coalesces concurrent lookups for the same meal name into one network call.
    /// Without this, MealPlanViewModel's whole-week preload and each visible
    /// MealImageView's own fetch race on first load and can both hit the Pexels API
    /// for the same meal before either has written the cache.
    private var inFlightRequests: [String: Task<String?, Never>] = [:]

    private init() {}

    private struct PexelsResponse: Decodable {
        struct Photo: Decodable {
            struct Src: Decodable { let large: String }
            let src: Src
        }
        let photos: [Photo]
    }

    private static func cacheKey(for mealName: String) -> String {
        let sanitized = mealName.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return cachePrefix + String(sanitized)
    }

    private func cachedImageURL(for mealName: String) -> String? {
        UserDefaults.standard.string(forKey: Self.cacheKey(for: mealName))
    }

    private func saveImageURL(_ url: String, for mealName: String) {
        UserDefaults.standard.set(url, forKey: Self.cacheKey(for: mealName))
    }

    private func search(query: String) async -> String? {
        var components = URLComponents(string: "\(Self.baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(Secrets.pexelsAPIKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(PexelsResponse.self, from: data)
            return decoded.photos.first?.src.large
        } catch {
            return nil
        }
    }

    /// Mirrors getFoodImage: cache first, then a meal-specific search, falling back to
    /// a generic "delicious food" search if that returns nothing. Swallows all
    /// failures and returns nil, matching the RN version's own catch-and-return-null.
    /// Concurrent callers for the same meal name share one in-flight lookup.
    func getFoodImage(mealName: String) async -> String? {
        guard !mealName.isEmpty else { return nil }

        if let cached = cachedImageURL(for: mealName) {
            return cached
        }

        let key = Self.cacheKey(for: mealName)
        if let existing = inFlightRequests[key] {
            return await existing.value
        }

        let task = Task<String?, Never> {
            if let url = await self.search(query: "\(mealName) food") {
                self.saveImageURL(url, for: mealName)
                return url
            }
            if let fallbackURL = await self.search(query: "delicious food") {
                self.saveImageURL(fallbackURL, for: mealName)
                return fallbackURL
            }
            return nil
        }
        inFlightRequests[key] = task

        let result = await task.value
        inFlightRequests[key] = nil
        return result
    }

    /// Mirrors preloadImages: fully parallel, per-meal failures swallowed.
    func preloadImages(_ meals: [Meal]) async {
        await withTaskGroup(of: Void.self) { group in
            for meal in meals where !meal.name.isEmpty {
                group.addTask { _ = await self.getFoodImage(mealName: meal.name) }
            }
        }
    }
}
