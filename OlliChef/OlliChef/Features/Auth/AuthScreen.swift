import SwiftUI

/// Placeholder — Sign in with Apple wiring lands in the Auth & Onboarding phase.
struct AuthScreen: View {
    var body: some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Text("OlliChef")
                .font(.system(size: AppTypography.displayXL, weight: .bold))
                .foregroundStyle(AppColor.brandSecondary)
            Text("Sign in with Apple")
                .font(.system(size: AppTypography.body))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBody)
    }
}
