import SwiftUI

/// Placeholder — the day-paged meal plan browser lands in the Chat + Meal Plan phase.
struct MealPlanScreen: View {
    var body: some View {
        Text("Meal Plan")
            .font(.system(size: AppTypography.headline))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceBody)
    }
}
