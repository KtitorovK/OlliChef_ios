import SwiftUI
import UIKit

/// In-memory cache for the actual downloaded image bytes, keyed by URL string.
/// PexelsService already caches the resolved *URL* persistently (UserDefaults), but
/// nothing previously cached the image itself — `AsyncImage` alone has no cross-view
/// cache, so every time a `MealImageView` was torn down and recreated (e.g. Chat's
/// `LazyVStack` discarding off-screen row state on every new message, confirmed live:
/// pictures visibly reloaded on every send) it re-fetched the same photo from
/// scratch. `NSCache` is thread-safe and evicts under memory pressure on its own.
private enum MealImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
}

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
    @State private var loadedImage: UIImage?
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
                defer { isLoading = false }
                guard let url = await PexelsService.shared.getFoodImage(mealName: mealName) else {
                    imageURL = nil
                    return
                }
                imageURL = url
                // Checked first, synchronously — this is the case that matters most:
                // a view instance recreated fresh (e.g. Chat's LazyVStack discarding
                // off-screen rows) resolves to the same URL PexelsService already
                // cached, and if the bytes are already in MealImageCache too, this
                // returns instantly with no visible reload at all.
                if let cached = MealImageCache.shared.object(forKey: url as NSString) {
                    loadedImage = cached
                    return
                }
                guard let (data, _) = try? await URLSession.shared.data(from: URL(string: url)!),
                      let image = UIImage(data: data) else { return }
                MealImageCache.shared.setObject(image, forKey: url as NSString)
                loadedImage = image
            }
    }

    @ViewBuilder
    private var content: some View {
        if let loadedImage {
            Image(uiImage: loadedImage).resizable().scaledToFill()
        } else if isLoading {
            placeholderTile {
                ProgressView().tint(AppColor.brandAccent)
            }
        } else {
            // Covers both "no URL found" and "URL found but the download failed" —
            // same fallback either way, matching AsyncImage's old error-phase behavior.
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
            .fill(AppColor.surfaceCard)
            .overlay(content())
    }
}
