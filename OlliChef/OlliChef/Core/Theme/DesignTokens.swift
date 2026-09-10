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

enum AppTypography {
    static let displayXL: CGFloat = 40
    static let title: CGFloat = 24
    static let headline: CGFloat = 20
    static let subhead: CGFloat = 18
    static let body: CGFloat = 16
    static let caption: CGFloat = 14
    static let label: CGFloat = 12
}
