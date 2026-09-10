import SwiftUI

private struct OnboardingSlideContent: Identifiable {
    let id: Int
    let imageName: String
    let headline: String
    let body: String
}

/// Ported from OnboardingScreen.tsx — same 4 slides, same copy. Hint overlays (the
/// "tap to send"/"tap Accept" callouts on slides 1 and 2) are left for a later polish
/// pass; the informational content and flow are what matters for this phase.
struct OnboardingScreen: View {
    let onComplete: () -> Void

    @State private var index = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var slides: [OnboardingSlideContent] {
        let suffix = isIPad ? "Ipad" : ""
        return [
            OnboardingSlideContent(
                id: 1,
                imageName: "Onboarding1\(suffix)",
                headline: "Meet Olli, your AI chef for easy meal planning",
                body: "Tell OlliChef what you want to eat, your diet, or your goals — and get a personalized meal plan in minutes."
            ),
            OnboardingSlideContent(
                id: 2,
                imageName: "Onboarding2\(suffix)",
                headline: "Review and accept your meal plan",
                body: "Scroll through your generated meals and tap Accept to save your plan in one place."
            ),
            OnboardingSlideContent(
                id: 3,
                imageName: "Onboarding3\(suffix)",
                headline: "Turn ideas into a real meal plan",
                body: "Review your generated meals, accept the plan, and keep everything organized in one place."
            ),
            OnboardingSlideContent(
                id: 4,
                imageName: "Onboarding4\(suffix)",
                headline: "Get your grocery list automatically",
                body: "Every accepted meal plan becomes a ready-to-use grocery list you can check off while shopping."
            ),
        ]
    }

    private var isLast: Bool { index == slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onComplete)
                    .font(.system(size: isIPad ? 18 : 16, weight: .medium))
                    .foregroundStyle(AppColor.brandPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { i, slide in
                    slideView(slide).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: AppSpacing.contentPadding) {
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? AppColor.brandPrimary : AppColor.textSecondary.opacity(0.35))
                            .frame(width: i == index ? 20 : 8, height: 8)
                    }
                }

                Button(action: isLast ? onComplete : goNext) {
                    Text(isLast ? "Get Started" : "Next")
                        .font(.system(size: isIPad ? 20 : 16, weight: .semibold))
                        .foregroundStyle(AppColor.textOnBrand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColor.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
                }
                .padding(.horizontal, isIPad ? 48 : AppSpacing.contentPadding)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppColor.surfaceBody)
    }

    private func goNext() {
        if index < slides.count - 1 {
            withAnimation { index += 1 }
        }
    }

    private func slideView(_ slide: OnboardingSlideContent) -> some View {
        VStack(spacing: AppSpacing.contentPadding) {
            Image(slide.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity)

            Text(slide.headline)
                .font(.system(size: AppTypography.title, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(slide.body)
                .font(.system(size: AppTypography.body))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppSpacing.contentPadding)
    }
}
