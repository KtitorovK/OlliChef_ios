import SwiftUI

/// Placeholder — real chat UI, meal-plan card rendering, and the accept flow land
/// in the Chat + Meal Plan phase.
struct ChatScreen: View {
    var body: some View {
        Text("Chat")
            .font(.system(size: AppTypography.headline))
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.surfaceBody)
    }
}
