import SwiftUI

/// Ported from theme/index.ts and theme/platform.ts. Colors resolve via Asset Catalog
/// color sets (light + dark already defined per-asset); spacing/typography use the iOS
/// branch of the original's Platform.select values, since Android no longer applies.
enum AppColor {
    static let brandPrimary = Color("BrandPrimary")
    static let brandSecondary = Color("BrandSecondary")
    static let surfaceBody = Color("SurfaceBody")
    static let surfaceHeader = Color("SurfaceHeader")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textOnBrand = Color("TextOnBrand")
    static let cardSurface = Color("CardSurface")
    static let border = Color("BorderColor")
    static let statusError = Color("StatusError")
    static let statusSuccess = Color("StatusSuccess")
    static let statusWarning = Color("StatusWarning")
}

enum AppSpacing {
    static let headerVertical: CGFloat = 8
    static let contentPadding: CGFloat = 14
    static let buttonVertical: CGFloat = 14
    static let buttonHorizontal: CGFloat = 24
    static let tabBarHeight: CGFloat = 57
    static let inputBottom: CGFloat = 24
}

enum AppRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 10
    static let large: CGFloat = 12
}

/// Ported from theme/platform.ts's typography scale, but as semantic text styles
/// rather than fixed point sizes — the original never supported Dynamic Type, and
/// SwiftUI's built-in styles (.title2, .title3, etc.) scale with the user's
/// accessibility text-size setting automatically. Mapped by closest default point
/// size to preserve the original's relative scale (displayXL > title > headline > ...).
enum AppTypography {
    static let displayXL: Font = .largeTitle   // ~34pt, was 40
    static let title: Font = .title2           // ~22pt, was 24
    static let headline: Font = .title3        // ~20pt, was 20 — exact match
    static let subhead: Font = .headline       // ~17pt, was 18
    static let body: Font = .body              // ~17pt, was 16
    static let caption: Font = .footnote       // ~13pt, was 14
    static let label: Font = .caption          // ~12pt, was 12 — exact match
}
