import Foundation

/// Ported from groceryService.ts: deterministic unit-aware ingredient merging, then a
/// single AI batch call for shopper-friendly naming/categorization, with a hard
/// fallback to the deterministic list if that call fails. Deliberately a plain Chat
/// Completions call — separate from ChatService's conversation, exactly like the RN
/// version kept it a one-shot, stateless request.
actor GroceryService {
    static let shared = GroceryService()

    private static let model = "gpt-4o-mini"
    private let client = APIClient(serviceName: "GroceryService")

    private init() {}

    // MARK: - Unit conversion tables

    private enum UnitFamily {
        case volume, weight, count, other
    }

    private static let volumeToML: [String: Double] = [
        "tsp": 5, "teaspoon": 5, "teaspoons": 5,
        "tbsp": 15, "tablespoon": 15, "tablespoons": 15,
        "cup": 240, "cups": 240,
        "fl oz": 30, "fluid oz": 30, "fluid ounce": 30, "fluid ounces": 30,
        "ml": 1, "milliliter": 1, "milliliters": 1, "millilitre": 1, "millilitres": 1,
        "l": 1000, "liter": 1000, "liters": 1000, "litre": 1000, "litres": 1000,
    ]

    private static let weightToGrams: [String: Double] = [
        "g": 1, "gram": 1, "grams": 1,
        "kg": 1000, "kilogram": 1000, "kilograms": 1000,
        "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
        "lb": 453.6, "lbs": 453.6, "pound": 453.6, "pounds": 453.6,
    ]

    private static let countUnits: Set<String> = [
        "piece", "pieces", "pcs", "pc",
        "unit", "units",
        "whole", "slice", "slices",
        "item", "items",
    ]

    private static func getUnitFamily(_ unit: String) -> UnitFamily {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        if volumeToML[u] != nil { return .volume }
        if weightToGrams[u] != nil { return .weight }
        if countUnits.contains(u) { return .count }
        return .other
    }

    private static func toBase(_ amount: Double, _ unit: String) -> (base: Double, family: UnitFamily) {
        let u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        if let factor = volumeToML[u] { return (amount * factor, .volume) }
        if let factor = weightToGrams[u] { return (amount * factor, .weight) }
        if countUnits.contains(u) { return (amount, .count) }
        return (amount, .other)
    }

    private static func toDisplayUnit(base: Double, family: UnitFamily, originalUnit: String) -> (amount: Double, unit: String) {
        switch family {
        case .volume:
            if base < 15 { return ((base / 5).rounded(), "tsp") }
            if base < 60 { return ((base / 15).rounded(), "tbsp") }
            if base < 480 { return (base.rounded(), "ml") }
            return (((base / 1000) * 10).rounded() / 10, "l")
        case .weight:
            if base < 1000 { return (base.rounded(), "g") }
            return (((base / 1000) * 10).rounded() / 10, "kg")
        case .count:
            return (base.rounded(), "piece")
        case .other:
            return ((base * 100).rounded() / 100, originalUnit)
        }
    }

    // MARK: - Steps 1-3: extract, normalize units, merge by name + unit family

    private struct MergedIngredient {
        var normalizedName: String
        var displayName: String
        var baseAmount: Double
        var unitFamily: UnitFamily
        var originalUnit: String
        var category: String
    }

    private static func extractAndMerge(_ mealPlan: MealPlan) -> [MergedIngredient] {
        var merged: [String: MergedIngredient] = [:]

        for day in mealPlan.days {
            for meal in day.meals {
                for ingredient in meal.ingredients {
                    let name = ingredient.name.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { continue }

                    let normalizedName = name.lowercased()
                    let rawUnit = (ingredient.unit ?? "").lowercased().trimmingCharacters(in: .whitespaces)
                    let amount = ingredient.amount ?? 0

                    let (base, family): (Double, UnitFamily) = (amount > 0 && !rawUnit.isEmpty)
                        ? toBase(amount, rawUnit)
                        : (amount, getUnitFamily(rawUnit))

                    let mergeKey = "\(normalizedName)__\(family)"
                    if var existing = merged[mergeKey] {
                        existing.baseAmount += base
                        merged[mergeKey] = existing
                    } else {
                        merged[mergeKey] = MergedIngredient(
                            normalizedName: normalizedName,
                            displayName: name,
                            baseAmount: base,
                            unitFamily: family,
                            originalUnit: rawUnit,
                            category: ingredient.category ?? "Other"
                        )
                    }
                }
            }
        }

        return Array(merged.values)
    }

    // MARK: - Step 4: convert base amounts back to display units

    private struct DisplayItem {
        var name: String
        var amount: Double
        var unit: String
        var category: String
    }

    private static func toDisplayItems(_ merged: [MergedIngredient]) -> [DisplayItem] {
        merged.map { item in
            let (amount, unit) = toDisplayUnit(base: item.baseAmount, family: item.unitFamily, originalUnit: item.originalUnit)
            return DisplayItem(name: item.displayName, amount: amount, unit: unit, category: item.category)
        }
    }

    // MARK: - Step 5a: deterministic userHas filter

    /// Mirrors isInUserHas: case-insensitive substring match either direction, so
    /// "eggs" matches "egg" and "beef" matches "beef strips".
    private static func isInUserHas(_ ingredientName: String, _ userHas: [String]) -> Bool {
        let norm = ingredientName.lowercased().trimmingCharacters(in: .whitespaces)
        return userHas.contains { entry in
            let hNorm = entry.lowercased().trimmingCharacters(in: .whitespaces)
            return norm == hNorm || norm.contains(hNorm) || hNorm.contains(norm)
        }
    }

    private static func filterUserHasItems(_ items: [DisplayItem], _ userHas: [String]) -> [DisplayItem] {
        guard !userHas.isEmpty else { return items }
        return items.filter { !isInUserHas($0.name, userHas) }
    }

    // MARK: - Step 5b: single AI batch call

    private struct AIGroceryItem: Decodable {
        let name: String
        let amount: Double?
        let unit: String?
        let category: String
        let note: String?
    }

    private struct ChatCompletionResult: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]?
    }

    /// Mirrors the RN regex strip: an optional leading ```/```json fence and a
    /// trailing ``` fence, each with surrounding whitespace trimmed.
    private static func stripMarkdownFences(_ text: String) -> String {
        var result = text
        if let range = result.range(of: #"^```(?:json)?\s*"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        if let range = result.range(of: #"\s*```$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callAIConversion(ingredients: [DisplayItem], userHas: [String]) async throws -> [AIGroceryItem] {
        let systemPrompt = await PromptManager.shared.groceryPrompt()

        let ingredientsJSON = ingredients.map { item -> [String: Any] in
            ["name": item.name, "amount": item.amount, "unit": item.unit, "category": item.category]
        }
        let userContent: [String: Any] = ["userHas": userHas, "ingredients": ingredientsJSON]
        let userContentData = try JSONSerialization.data(withJSONObject: userContent)
        let userContentString = String(data: userContentData, encoding: .utf8) ?? "{}"

        var request = URLRequest(url: URL(string: "\(Secrets.firebaseOpenAIProxyURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContentString],
            ],
            "max_tokens": 1500,
            "temperature": 0.2,
        ])

        let (data, _) = try await RetryHelpers.retryRequest {
            try await self.client.send(request)
        }

        let result = try JSONDecoder().decode(ChatCompletionResult.self, from: data)
        let raw = Self.stripMarkdownFences(result.choices?.first?.message.content ?? "")

        guard let jsonData = raw.data(using: .utf8) else {
            throw ChatServiceError.apiError("AI response is not valid UTF-8")
        }
        let items = try JSONDecoder().decode([AIGroceryItem].self, from: jsonData)
        return items.filter { !$0.name.isEmpty && !$0.category.isEmpty }
    }

    // MARK: - Map to GroceryItem

    private static func toGroceryItems(_ items: [DisplayItem]) -> [GroceryItem] {
        items.map { GroceryItem(name: $0.name, category: $0.category, amount: $0.amount, unit: $0.unit, checked: false, notes: nil) }
    }

    private static func toGroceryItems(fromAI items: [AIGroceryItem]) -> [GroceryItem] {
        items.map { GroceryItem(name: $0.name, category: $0.category.isEmpty ? "Other" : $0.category, amount: $0.amount, unit: $0.unit, checked: false, notes: $0.note) }
    }

    // MARK: - Public API

    enum GroceryServiceError: Error {
        case noIngredients
    }

    /// Mirrors generateGroceryListForPlan: merge -> convert -> filter userHas -> AI batch
    /// call, with a silent fallback to the deterministic list on any AI failure. Creates
    /// the Firestore document itself, matching the RN function's own side effect.
    func generateGroceryListForPlan(_ mealPlan: MealPlan) async throws -> GroceryList {
        let merged = Self.extractAndMerge(mealPlan)
        guard !merged.isEmpty else { throw GroceryServiceError.noIngredients }

        let displayItems = Self.toDisplayItems(merged)
        let userHas = mealPlan.userHas ?? []
        let needToBuy = Self.filterUserHasItems(displayItems, userHas)

        var groceryItems: [GroceryItem]
        do {
            let aiItems = try await callAIConversion(ingredients: needToBuy, userHas: userHas)
            let aiFiltered = aiItems.filter { !Self.isInUserHas($0.name, userHas) }
            groceryItems = Self.toGroceryItems(fromAI: aiFiltered)
            if groceryItems.isEmpty {
                groceryItems = Self.toGroceryItems(needToBuy)
            }
        } catch {
            handleError(error, context: ErrorContext(location: "GroceryService", action: "callAIConversion"))
            groceryItems = Self.toGroceryItems(needToBuy)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let groceryList = GroceryList(
            id: UUID().uuidString,
            mealPlanId: mealPlan.id,
            items: groceryItems,
            createdAt: now,
            updatedAt: now
        )

        try await GroceryListStorageService.create(groceryList)
        return groceryList
    }
}
