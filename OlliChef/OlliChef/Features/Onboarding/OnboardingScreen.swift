import SwiftUI

private struct OnboardingSlideContent: Identifiable {
    let id: Int
    /// Base name of a same-content iPhone/iPad screenshot pair — resolved to
    /// "<name>" or "<name>Ipad" by the slide view below.
    let screenshotBaseName: String
    let headline: String
    let body: String
}

/// Went through several passes this session: RN's screenshot-in-a-card slides
/// (`OnboardingScreen.tsx`'s `onboarding_1.png` etc.) → icon illustrations → a
/// screenshot inside a drawn device bezel → the screenshot full-bleed behind the text
/// with a dark scrim → this: the screenshot stays large and full-bleed (top ~60% of
/// the screen, edge to edge) but at its own real colors, with the text living in a
/// plain solid panel below it instead of overlaid on top — the scrim version kept the
/// screenshot legible but always looked muddy/grey, since a gradient dark enough to
/// protect white text over an unpredictable photo has to cover most of the image.
/// Each screenshot is a real capture from this session (today's meal-plan image
/// sizing, the redesigned Recipe Story screen) with its own status bar/tab bar
/// cropped off beforehand, so the only chrome visible is the device's own.
struct OnboardingScreen: View {
    let onComplete: () -> Void

    @State private var index = 0

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private let slides: [OnboardingSlideContent] = [
        OnboardingSlideContent(
            id: 0,
            screenshotBaseName: "OnboardingChat",
            headline: "Meet Olli, your AI chef for easy meal planning",
            body: "Tell OlliChef what you want to eat, your diet, or your goals — and get a personalized meal plan in minutes."
        ),
        OnboardingSlideContent(
            id: 1,
            screenshotBaseName: "OnboardingMealPlan",
            headline: "A full week of meals, planned for you",
            body: "Chat your goals and get a personalized weekly plan — accept it in one tap to save it to your calendar."
        ),
        OnboardingSlideContent(
            id: 2,
            screenshotBaseName: "OnboardingRecipe",
            headline: "Cook with confidence, step by step",
            body: "Every meal comes with clear, AI-written instructions and nutrition info — no guesswork in the kitchen."
        ),
        OnboardingSlideContent(
            id: 3,
            screenshotBaseName: "OnboardingGroceries",
            headline: "Get your grocery list automatically",
            body: "Every accepted meal plan becomes a ready-to-use grocery list you can check off while shopping."
        ),
    ]

    private var isLast: Bool { index == slides.count - 1 }
    /// The screenshot's own share of the screen — the rest goes to the plain text
    /// panel below it.
    private let imageFraction: CGFloat = 0.58

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    TabView(selection: $index) {
                        ForEach(slides) { slide in
                            slideImage(slide).tag(slide.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    Button("Skip", action: onComplete)
                        .font(AppTypography.cardTitle.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.32), in: Capsule())
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                        .accessibilityIdentifier("onboarding.skip")
                }
                .frame(height: geo.size.height * imageFraction)
                .ignoresSafeArea(edges: .top)

                VStack(spacing: AppSpacing.md) {
                    VStack(spacing: AppSpacing.xs) {
                        Text(slides[index].headline)
                            .font(.system(size: isIPad ? 40 : 26, weight: .bold))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding.headline")

                        Text(slides[index].body)
                            .font(.system(size: isIPad ? 22 : 17))
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: isIPad ? 620 : 340)

                    HStack(spacing: 8) {
                        ForEach(slides) { slide in
                            Capsule()
                                .fill(slide.id == index ? AppColor.brandAction : AppColor.textSecondary.opacity(0.35))
                                .frame(width: slide.id == index ? 20 : 8, height: 8)
                        }
                    }

                    Button(action: isLast ? onComplete : goNext) {
                        Text(isLast ? "Get Started" : "Next")
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(AppColor.textOnBrand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColor.brandAction)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
                    }
                    .padding(.horizontal, isIPad ? 64 : AppSpacing.contentPadding)
                    // Same identifier throughout even though the label changes ("Next"
                    // → "Get Started") — per the testing plan's own rule, tests key off
                    // a stable identifier, never the display text.
                    .accessibilityIdentifier("onboarding.continue")
                }
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.surfaceBody)
            }
        }
        .background(AppColor.surfaceBody)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func goNext() {
        if index < slides.count - 1 {
            withAnimation { index += 1 }
        }
    }

    private func slideImage(_ slide: OnboardingSlideContent) -> some View {
        let imageName = isIPad ? "\(slide.screenshotBaseName)Ipad" : slide.screenshotBaseName
        return GeometryReader { geo in
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                // Anchored to the top, not centered — each screenshot was already
                // cropped to drop its status bar/nav bar, so the top of the source
                // image is exactly where the meaningful content starts; a center-crop
                // here would instead center on empty space further down the screen
                // (e.g. below a short chat thread) and clip the real content off.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
        }
    }
}
