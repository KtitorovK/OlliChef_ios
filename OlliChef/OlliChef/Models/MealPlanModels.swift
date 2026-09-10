import Foundation

/// Ported from src/types/mealPlan.ts. Pure data shape only — parsing, validation, and
/// Firestore CRUD land in the Chat + Meal Plan phase, not here.

struct Ingredient: Codable, Hashable {
    var name: String
    var category: String?
    var amount: Double?
    var unit: String?
    var notes: String?
}

struct NutritionInfo: Codable, Hashable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

struct Meal: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var ingredients: [Ingredient]
    var instructions: String?
    var imageUrl: String?
    var story: String?
    var prepTime: Double?
    var cookTime: Double?
    var servings: Double?
    var tags: [String]?
    var notes: String?
    var nutritionInfo: NutritionInfo?
}

struct DayMeals: Codable, Hashable {
    var date: String
    var day: String?
    var meals: [Meal]
}

struct MealPlan: Codable, Hashable, Identifiable {
    var id: String
    var startDate: String
    var endDate: String
    var days: [DayMeals]
    var createdAt: String
    var updatedAt: String
    var notes: String?
    /// Ingredients the user mentioned having at home — excluded from the generated grocery list.
    var userHas: [String]?
}
