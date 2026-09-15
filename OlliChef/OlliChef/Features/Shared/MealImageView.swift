import SwiftUI

/// Ported from MealImage.tsx: fetches a meal's photo via PexelsService, showing a
/// spinner while looking it up and a fallback icon tile if none was found.
enum MealImageSize {
    case small, medium, large

    fileprivate var box: (width: CGFloat, height: CGFloat, radius: CGFloat) {
        switch self {
        case .small: return (60, 60, 8)
        case .medium: return (100, 80, 10)
        case .large: return (200, 150, 12)
        }
    }

    fileprivate var iconSize: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 32
        case .large: return 48
        }
    }
}

struct MealImageView: View {
    let mealName: String
    var size: MealImageSize = .medium
    /// Mirrors MealImage.tsx's `style`/`containerStyle` override — the chat meal-plan
    /// card shrinks the otherwise-60×60 "small" variant down to a 32×32 thumbnail this
    /// way. A nil width mirrors RN's `width: '100%'` hero override — full available
    /// width rather than a fixed box, used by RecipeStoryScreen.
    var overrideBox: (width: CGFloat?, height: CGFloat, radius: CGFloat)?

    @State private var imageURL: String?
    @State private var isLoading = true

    private var boxHeight: CGFloat { overrideBox?.height ?? size.box.height }
    private var boxRadius: CGFloat { overrideBox?.radius ?? size.box.radius }

    /// Nil only when `overrideBox` is present with an explicitly nil width (the
    /// full-bleed hero case) — distinct from no override at all, which falls back to
    /// the size enum's fixed width. `??` alone would wrongly collapse both cases.
    private var resolvedWidth: CGFloat? {
        if let overrideBox { return overrideBox.width }
        return size.box.width
    }

    var body: some View {
        // scaledToFill() needs a concrete width to scale against — `.frame(maxWidth:
        // .infinity)` alone doesn't reliably propagate one down to AsyncImage, so the
        // full-bleed case resolves to the actual screen width instead of staying flexible.
        let width = resolvedWidth ?? UIScreen.main.bounds.width
        content
            .frame(width: width, height: boxHeight)
            .clipShape(RoundedRectangle(cornerRadius: boxRadius))
            .task(id: mealName) {
                isLoading = true
                imageURL = await PexelsService.shared.getFoodImage(mealName: mealName)
                isLoading = false
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            placeholderTile {
                ProgressView().tint(AppColor.brandPrimary)
            }
        } else if let imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    placeholderTile { fallbackIcon }
                } else {
                    placeholderTile { EmptyView() }
                }
            }
        } else {
            placeholderTile { fallbackIcon }
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: size.iconSize * 0.6))
            .foregroundStyle(AppColor.textSecondary)
    }

    private func placeholderTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: boxRadius)
            .fill(AppColor.cardSurface)
            .overlay(content())
    }
}
