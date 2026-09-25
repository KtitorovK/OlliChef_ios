import Foundation

nonisolated enum MealPlanParser {
    /// Ported from nutritionUtils.ts's calculateCaloriesFromPFC.
    static func calculateCalories(protein: Double = 0, fat: Double = 0, carbs: Double = 0) -> Double {
        protein * 4 + fat * 9 + carbs * 4
    }

    /// Ported from mealPlanUtils.ts's parseMealPlanFromAssistantJson.
    static func parse(_ json: [String: Any]) -> MealPlan? {
        guard let mealPlanJSON = json["meal_plan"] as? [String: Any] else { return nil }

        var startDate = ""
        var endDate = ""
        if let week = mealPlanJSON["week"] as? String,
           let range = week.range(of: #"^([0-9\-]+) to ([0-9\-]+)$"#, options: .regularExpression) {
            let parts = week[range].components(separatedBy: " to ")
            if parts.count == 2 {
                startDate = parts[0]
                endDate = parts[1]
            }
        }

        let daysJSON = mealPlanJSON["days"] as? [[String: Any]] ?? []
        let days: [DayMeals] = daysJSON.map { dayJSON in
            let date = dayJSON["date"] as? String ?? ""
            let day = dayJSON["day"] as? String
            let mealsJSON = dayJSON["meals"] as? [[String: Any]] ?? []

            let meals: [Meal] = mealsJSON.compactMap { mealJSON in
                guard let name = mealJSON["name"] as? String else { return nil }

                let ingredientsJSON = mealJSON["ingredients"] as? [[String: Any]] ?? []
                let ingredients = ingredientsJSON.map { ing in
                    Ingredient(
                        name: ing["name"] as? String ?? "",
                        category: ing["category"] as? String,
                        amount: (ing["amount"] as? NSNumber)?.doubleValue,
                        unit: ing["unit"] as? String,
                        notes: nil
                    )
                }

                let protein = (mealJSON["protein_g"] as? NSNumber)?.doubleValue
                let fat = (mealJSON["fat_g"] as? NSNumber)?.doubleValue
                let carbs = (mealJSON["carbs_g"] as? NSNumber)?.doubleValue
                let nutrition: NutritionInfo? = (protein != nil || fat != nil || carbs != nil)
                    ? NutritionInfo(
                        calories: (mealJSON["calories"] as? NSNumber)?.doubleValue
                            ?? calculateCalories(protein: protein ?? 0, fat: fat ?? 0, carbs: carbs ?? 0),
                        protein: protein,
                        carbs: carbs,
                        fat: fat
                    )
                    : nil

                return Meal(
                    id: (mealJSON["id"] as? String) ?? "\(date)-\(name)",
                    name: name,
                    type: mealJSON["type"] as? String,
                    ingredients: ingredients,
                    instructions: nil,
                    imageUrl: (mealJSON["imageUrl"] as? String) ?? (mealJSON["image"] as? String),
                    story: nil,
                    prepTime: nil,
                    cookTime: nil,
                    servings: nil,
                    tags: nil,
                    notes: nil,
                    nutritionInfo: nutrition
                )
            }

            return DayMeals(date: date, day: day, meals: meals)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        return MealPlan(
            id: "meal-plan-\(startDate)",
            startDate: startDate,
            endDate: endDate,
            days: days,
            createdAt: now,
            updatedAt: now,
            notes: mealPlanJSON["notes"] as? String,
            userHas: mealPlanJSON["userHas"] as? [String]
        )
    }

    /// The dynamic prompt instructs the model to always return the complete updated
    /// week when the user asks to change part of an existing plan, never just the
    /// changed part — but that's a prompt instruction, not something Structured
    /// Outputs' schema can enforce (the schema has no way to express "must contain
    /// every day the previous plan had"). Confirmed live: after a few clarifying
    /// questions, the model returned only the one edited day. Accepting that
    /// response as-is would silently drop the rest of the week from the saved plan,
    /// so this splices `updated`'s days into `previous`'s by date — `updated` wins
    /// on any date both share (that's the actual edit), and any date only
    /// `previous` has is carried forward unchanged.
    ///
    /// Only merges when at least one date overlaps between the two plans — a
    /// completely disjoint date range (e.g. "actually, plan me a totally different
    /// week starting in November") is treated as an intentional new plan, not a
    /// partial edit, and returned unchanged.
    static func reconcile(updated: MealPlan, previous: MealPlan?) -> MealPlan {
        guard let previous else { return updated }

        let updatedDates = Set(updated.days.map(\.date))
        let previousDates = Set(previous.days.map(\.date))
        guard !updatedDates.isDisjoint(with: previousDates) else { return updated }

        var byDate: [String: DayMeals] = [:]
        for day in previous.days { byDate[day.date] = day }
        for day in updated.days { byDate[day.date] = day }

        var merged = updated
        merged.days = byDate.values.sorted { $0.date < $1.date }
        return merged
    }
}
