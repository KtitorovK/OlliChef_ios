import Foundation
import Testing
@testable import OlliChef

struct IngredientTests {
    @Test func displayLabelWithWholeAmount() {
        let ingredient = Ingredient(name: "eggs", amount: 4, unit: "large")
        #expect(ingredient.displayLabel == "4 large eggs")
    }

    @Test func displayLabelWithFractionalAmount() {
        let ingredient = Ingredient(name: "flour", amount: 1.5, unit: "cup")
        #expect(ingredient.displayLabel == "1.5 cup flour")
    }

    @Test func displayLabelWithNoUnit() {
        let ingredient = Ingredient(name: "onion", amount: 2)
        #expect(ingredient.displayLabel == "2 onion")
    }

    @Test func displayLabelWithNoAmountFallsBackToNameOnly() {
        let ingredient = Ingredient(name: "salt")
        #expect(ingredient.displayLabel == "salt")
    }
}

struct NutritionInfoTests {
    @Test func summaryTextWithAllFields() {
        let info = NutritionInfo(calories: 235, protein: 20, carbs: 5, fat: 15)
        #expect(info.summaryText == "P 20g • F 15g • C 5g • 235 kcal")
    }

    @Test func summaryTextWithOnlyCalories() {
        let info = NutritionInfo(calories: 100)
        #expect(info.summaryText == "100 kcal")
    }

    @Test func summaryTextWithNoFieldsIsEmpty() {
        let info = NutritionInfo()
        #expect(info.summaryText == "")
    }
}

struct DayMealsTests {
    @Test func dateValueParsesUTCDateOnlyString() {
        let day = DayMeals(date: "2026-09-12", day: nil, meals: [])
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: day.dateValue!
        )
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 12)
    }

    @Test func dateValueIsNilForMalformedDate() {
        let day = DayMeals(date: "not-a-date", day: nil, meals: [])
        #expect(day.dateValue == nil)
    }

    @Test func labelsFallBackToRawDateStringWhenUnparseable() {
        let day = DayMeals(date: "garbage", day: nil, meals: [])
        #expect(day.fullWeekdayLabel == "garbage")
        #expect(day.shortWeekdayLabel == "garbage")
        #expect(day.pillWeekdayLabel == "garbage")
        // pillDateLabel is the one exception — it falls back to "", not the raw string,
        // since it's meant to be a short chip label with no room for a raw ISO string.
        #expect(day.pillDateLabel == "")
    }

    @Test func labelsFormatAKnownDateCorrectly() {
        // 2026-09-12 is a Saturday.
        let day = DayMeals(date: "2026-09-12", day: nil, meals: [])
        #expect(day.fullWeekdayLabel == "Saturday, Sep 12")
        #expect(day.shortWeekdayLabel == "Sat, Sep 12")
        #expect(day.pillWeekdayLabel == "Sat")
        #expect(day.pillDateLabel == "12 Sep")
    }

    @Test func isTodayTrueForTodaysDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let today = formatter.string(from: Date())
        let day = DayMeals(date: today, day: nil, meals: [])
        #expect(day.isToday)
    }

    @Test func isTodayFalseForAnotherDate() {
        let day = DayMeals(date: "2020-01-01", day: nil, meals: [])
        #expect(!day.isToday)
    }
}
