import SwiftUI

/// Placeholder — the AI-generated recipe story and its cache land in the
/// Recipe + Grocery phase.
struct RecipeStoryScreen: View {
    let meal: Meal

    var body: some View {
        Text(meal.name)
            .font(AppTypography.headline)
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceBody)
    }
}
