import Foundation

/// Ported from src/types/mealPlan.ts. Pure data shape only — parsing, validation, and
/// Firestore CRUD land in the Chat + Meal Plan phase, not here.

nonisolated struct Ingredient: Codable, Hashable {
    var name: String
    var category: String?
    var amount: Double?
    var unit: String?
    var notes: String?

    /// e.g. "4 large eggs", or just the name when no amount is known.
    var displayLabel: String {
        guard let amount else { return name }
        let amountText = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(amount)
        return [amountText, unit, name].compactMap { $0 }.joined(separator: " ")
    }
}

nonisolated struct NutritionInfo: Codable, Hashable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    /// Mirrors NutritionInfo.tsx's compact summary line, e.g. "P 20g • F 15g • C 60g • 235 kcal".
    var summaryText: String {
        var parts: [String] = []
        if let protein { parts.append("P \(Int(protein))g") }
        if let fat { parts.append("F \(Int(fat))g") }
        if let carbs { parts.append("C \(Int(carbs))g") }
        if let calories { parts.append("\(Int(calories)) kcal") }
        return parts.joined(separator: " • ")
    }
}

nonisolated struct Meal: Codable, Hashable, Identifiable {
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

nonisolated struct DayMeals: Codable, Hashable {
    var date: String
    var day: String?
    var meals: [Meal]

    /// `date` is a plain "yyyy-MM-dd" string (no time component) throughout the
    /// Firestore contract and the AI's JSON output — parsed in UTC to avoid the
    /// local timezone shifting it to the wrong calendar day.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var dateValue: Date? {
        Self.dateFormatter.date(from: date)
    }

    var isToday: Bool {
        guard let dateValue else { return false }
        return Calendar.current.isDateInToday(dateValue)
    }

    /// Mirrors DayHeader's formatDayHeader: "Monday, Sep 15". Falls back to the raw
    /// date string if it doesn't parse, matching the RN screen's own fallback.
    var fullWeekdayLabel: String {
        guard let dateValue else { return date }
        return Self.fullWeekdayFormatter.string(from: dateValue)
    }

    /// Mirrors the chat meal-plan card's day header date piece: "Mon, Sep 15".
    var shortWeekdayLabel: String {
        guard let dateValue else { return date }
        return Self.shortWeekdayFormatter.string(from: dateValue)
    }

    /// Mirrors the day-selector pill's weekday line: "Mon".
    var pillWeekdayLabel: String {
        guard let dateValue else { return date }
        return Self.pillWeekdayFormatter.string(from: dateValue)
    }

    /// Mirrors formatShortDate: "15 Sep".
    var pillDateLabel: String {
        guard let dateValue else { return "" }
        return Self.pillDateFormatter.string(from: dateValue)
    }

    private static let fullWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let shortWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let pillWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let pillDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

nonisolated struct MealPlan: Codable, Hashable, Identifiable {
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
