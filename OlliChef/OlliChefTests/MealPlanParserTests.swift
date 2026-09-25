import Foundation
import Testing
@testable import OlliChef

struct MealPlanParserCalorieTests {
    @Test func calculateCaloriesFromMacros() {
        // 4 kcal/g protein, 9 kcal/g fat, 4 kcal/g carbs — mirrors nutritionUtils.ts exactly.
        let calories = MealPlanParser.calculateCalories(protein: 20, fat: 15, carbs: 5)
        let expected: Double = 20 * 4 + 15 * 9 + 5 * 4
        #expect(calories == expected)
    }

    @Test func calculateCaloriesDefaultsMissingMacrosToZero() {
        #expect(MealPlanParser.calculateCalories(protein: 10) == 40)
    }
}

struct MealPlanParserParseTests {
    private func decodeJSON(_ string: String) -> [String: Any] {
        let data = string.data(using: .utf8)!
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func returnsNilWhenMealPlanKeyMissing() {
        let json = decodeJSON(#"{"type": "JSON"}"#)
        #expect(MealPlanParser.parse(json) == nil)
    }

    @Test func parsesWeekRangeIntoStartAndEndDates() {
        let json = decodeJSON(#"""
        {"meal_plan": {"week": "2026-09-12 to 2026-09-18", "days": []}}
        """#)
        let plan = MealPlanParser.parse(json)
        #expect(plan?.startDate == "2026-09-12")
        #expect(plan?.endDate == "2026-09-18")
        #expect(plan?.id == "meal-plan-2026-09-12")
    }

    @Test func leavesDatesEmptyWhenWeekStringDoesntMatchExpectedFormat() {
        let json = decodeJSON(#"""
        {"meal_plan": {"week": "sometime next week", "days": []}}
        """#)
        let plan = MealPlanParser.parse(json)
        #expect(plan?.startDate == "")
        #expect(plan?.endDate == "")
    }

    @Test func parsesADayWithMealsIngredientsAndNutrition() {
        let json = decodeJSON(#"""
        {
          "meal_plan": {
            "week": "2026-09-12 to 2026-09-18",
            "days": [
              {
                "date": "2026-09-12",
                "day": "Saturday",
                "meals": [
                  {
                    "name": "Mediterranean Omelet",
                    "type": "breakfast",
                    "protein_g": 20,
                    "fat_g": 15,
                    "carbs_g": 5,
                    "calories": 235,
                    "ingredients": [
                      {"name": "eggs", "amount": 3, "unit": "large", "category": "dairy"}
                    ]
                  }
                ]
              }
            ]
          }
        }
        """#)
        let plan = MealPlanParser.parse(json)
        #expect(plan?.days.count == 1)

        let day = plan?.days.first
        #expect(day?.date == "2026-09-12")
        #expect(day?.day == "Saturday")
        #expect(day?.meals.count == 1)

        let meal = day?.meals.first
        #expect(meal?.name == "Mediterranean Omelet")
        #expect(meal?.type == "breakfast")
        #expect(meal?.id == "2026-09-12-Mediterranean Omelet")
        #expect(meal?.nutritionInfo?.calories == 235)
        #expect(meal?.nutritionInfo?.protein == 20)
        #expect(meal?.ingredients.first?.name == "eggs")
        #expect(meal?.ingredients.first?.amount == 3)
    }

    @Test func fallsBackToCalculatedCaloriesWhenNotProvided() {
        let json = decodeJSON(#"""
        {"meal_plan": {"days": [{"date": "2026-09-12", "meals": [
            {"name": "Toast", "protein_g": 5, "fat_g": 10, "carbs_g": 20}
        ]}]}}
        """#)
        let meal = MealPlanParser.parse(json)?.days.first?.meals.first
        let expected: Double = 5 * 4 + 10 * 9 + 20 * 4
        #expect(meal?.nutritionInfo?.calories == expected)
    }

    @Test func nutritionInfoIsNilWhenNoMacrosProvidedAtAll() {
        let json = decodeJSON(#"""
        {"meal_plan": {"days": [{"date": "2026-09-12", "meals": [
            {"name": "Mystery Dish"}
        ]}]}}
        """#)
        let meal = MealPlanParser.parse(json)?.days.first?.meals.first
        #expect(meal?.nutritionInfo == nil)
    }

    @Test func skipsMealsWithNoName() {
        let json = decodeJSON(#"""
        {"meal_plan": {"days": [{"date": "2026-09-12", "meals": [
            {"protein_g": 10},
            {"name": "Has A Name"}
        ]}]}}
        """#)
        let meals = MealPlanParser.parse(json)?.days.first?.meals
        #expect(meals?.count == 1)
        #expect(meals?.first?.name == "Has A Name")
    }

    @Test func fallsBackToImageFieldWhenImageUrlMissing() {
        let json = decodeJSON(#"""
        {"meal_plan": {"days": [{"date": "2026-09-12", "meals": [
            {"name": "Toast", "image": "https://example.com/toast.jpg"}
        ]}]}}
        """#)
        let meal = MealPlanParser.parse(json)?.days.first?.meals.first
        #expect(meal?.imageUrl == "https://example.com/toast.jpg")
    }

    @Test func carriesOverNotesAndUserHas() {
        let json = decodeJSON(#"""
        {"meal_plan": {"days": [], "notes": "no shellfish", "userHas": ["olive oil", "salt"]}}
        """#)
        let plan = MealPlanParser.parse(json)
        #expect(plan?.notes == "no shellfish")
        #expect(plan?.userHas == ["olive oil", "salt"])
    }
}

/// Covers the prompt-compliance safety net: confirmed live, asking the AI to edit
/// part of a plan can still come back with only the edited day instead of the full
/// week the prompt asks for — `reconcile` splices the gap shut by date.
struct MealPlanParserReconcileTests {
    private func plan(_ dates: [String]) -> MealPlan {
        MealPlan(
            id: "meal-plan-\(dates.first ?? "")",
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            days: dates.map { DayMeals(date: $0, day: nil, meals: []) },
            createdAt: "",
            updatedAt: ""
        )
    }

    @Test func fillsInDaysMissingFromAnOverlappingEdit() {
        let fullWeek = plan(["2026-09-28", "2026-09-29", "2026-09-30"])
        let editedMondayOnly = plan(["2026-09-28"])

        let reconciled = MealPlanParser.reconcile(updated: editedMondayOnly, previous: fullWeek)

        #expect(reconciled.days.map(\.date) == ["2026-09-28", "2026-09-29", "2026-09-30"])
    }

    @Test func updatedDayWinsOverPreviousOnTheSameDate() {
        let previous = MealPlan(
            id: "p", startDate: "2026-09-28", endDate: "2026-09-28",
            days: [DayMeals(date: "2026-09-28", day: "Old", meals: [])],
            createdAt: "", updatedAt: ""
        )
        let updated = MealPlan(
            id: "u", startDate: "2026-09-28", endDate: "2026-09-28",
            days: [DayMeals(date: "2026-09-28", day: "New", meals: [])],
            createdAt: "", updatedAt: ""
        )

        let reconciled = MealPlanParser.reconcile(updated: updated, previous: previous)

        #expect(reconciled.days.first?.day == "New")
    }

    @Test func doesNotMergeCompletelyDisjointDateRanges() {
        // A genuinely new plan for a different period (e.g. "plan me November
        // instead") shouldn't get glued onto the old week.
        let septemberWeek = plan(["2026-09-28", "2026-09-29"])
        let novemberWeek = plan(["2026-11-02", "2026-11-03"])

        let reconciled = MealPlanParser.reconcile(updated: novemberWeek, previous: septemberWeek)

        #expect(reconciled.days.map(\.date) == ["2026-11-02", "2026-11-03"])
    }

    @Test func returnsUpdatedUnchangedWhenNoPreviousPlanExists() {
        let onlyPlan = plan(["2026-09-28"])
        let reconciled = MealPlanParser.reconcile(updated: onlyPlan, previous: nil)
        #expect(reconciled.days.map(\.date) == ["2026-09-28"])
    }
}
