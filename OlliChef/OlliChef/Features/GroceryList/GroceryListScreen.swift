import SwiftUI

/// Placeholder — the aggregated shopping checklist lands in the Recipe + Grocery phase.
struct GroceryListScreen: View {
    var body: some View {
        Text("Groceries")
            .font(.system(size: AppTypography.headline))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceBody)
    }
}
