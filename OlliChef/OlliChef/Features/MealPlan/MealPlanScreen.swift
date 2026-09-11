import SwiftUI

/// Ported from MealPlanScreen.tsx: fetches the plan covering today (or the closest
/// future one), day-paged. Full parity with the original's paging gestures/animation
/// is a later design pass — this establishes the real data flow and Firestore contract.
struct MealPlanScreen: View {
    @StateObject private var viewModel = MealPlanViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let mealPlan = viewModel.mealPlan {
                TabView {
                    ForEach(mealPlan.days, id: \.date) { day in
                        dayView(day)
                    }
                }
                .tabViewStyle(.page)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBody)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Image("EmptyMealPlan")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
            Text("No meal plan yet")
                .font(.system(size: AppTypography.subhead, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("Ask Olli in Chat to plan your week")
                .font(.system(size: AppTypography.body))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.contentPadding)
    }

    private func dayView(_ day: DayMeals) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.contentPadding) {
                Text(day.day ?? day.date)
                    .font(.system(size: AppTypography.title, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(day.meals) { meal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.type?.capitalized ?? "Meal")
                            .font(.system(size: AppTypography.label, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                        Text(meal.name)
                            .font(.system(size: AppTypography.subhead, weight: .medium))
                            .foregroundStyle(AppColor.textPrimary)
                        if let nutrition = meal.nutritionInfo {
                            Text(nutritionSummary(nutrition))
                                .font(.system(size: AppTypography.caption))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppColor.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
                }
            }
            .padding(AppSpacing.contentPadding)
        }
    }

    private func nutritionSummary(_ nutrition: NutritionInfo) -> String {
        var parts: [String] = []
        if let protein = nutrition.protein { parts.append("P \(Int(protein))g") }
        if let fat = nutrition.fat { parts.append("F \(Int(fat))g") }
        if let carbs = nutrition.carbs { parts.append("C \(Int(carbs))g") }
        if let calories = nutrition.calories { parts.append("\(Int(calories)) kcal") }
        return parts.joined(separator: " • ")
    }
}
