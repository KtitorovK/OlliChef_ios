import SwiftUI

/// Placeholder — real onboarding content lands in the Auth & Onboarding phase.
struct OnboardingScreen: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Text("Onboarding")
                .font(.system(size: AppTypography.title, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Button("Continue", action: onComplete)
                .buttonStyle(.borderedProminent)
                .tint(AppColor.brandPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surfaceBody)
    }
}
