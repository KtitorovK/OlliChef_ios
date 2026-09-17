import SwiftUI

/// App-wide semantic color palette. Every value resolves via an Asset Catalog color
/// set with its own light + dark appearance — never construct a `Color` from raw
/// components in a view; add or edit the color set instead.
///
/// Green has three distinct roles, deliberately kept separate rather than one
/// overloaded "brand green": `brandAccent` is decorative only (icons, small
/// indicators — never large surfaces or normal-size text, since it doesn't carry
/// enough contrast for that), `brandAction` is every interactive control (buttons,
/// links, checkboxes), and `brandForest` is reserved for strong selected states and
/// headings. `brandTint`/`brandTintStrong` are the subtle large-area green
/// backgrounds (unselected day chips, grocery category headers) that keep those
/// surfaces from reading as solid saturated green blocks.
enum AppColor {
    static let brandAccent = Color("BrandAccent")
    static let brandAction = Color("BrandAction")
    static let brandForest = Color("BrandForest")
    static let brandTint = Color("BrandTint")
    static let brandTintStrong = Color("BrandTintStrong")

    static let surfaceBody = Color("SurfaceBody")
    static let surfaceHeader = Color("SurfaceHeader")
    static let surfaceCard = Color("SurfaceCard")
    static let surfaceSelected = Color("SurfaceSelected")

    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    static let textOnBrand = Color("TextOnBrand")

    static let divider = Color("Divider")

    static let statusError = Color("StatusError")
    static let statusSuccess = Color("StatusSuccess")
    static let statusWarning = Color("StatusWarning")
}

/// Centralized spacing scale. Prefer these over literal numbers in `.padding()`/
/// stack `spacing:` wherever a value lines up with the scale; `contentPadding` and
/// the `button*` tokens stay as their own named constants since they're an
/// established, still-accurate semantic (not just an alias for one scale step).
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40

    static let contentPadding: CGFloat = 14
    static let buttonVertical: CGFloat = 14
    static let buttonHorizontal: CGFloat = 24
}

/// Centralized corner-radius scale.
enum AppRadius {
    static let small: CGFloat = 10
    static let image: CGFloat = 12
    static let card: CGFloat = 18
    static let large: CGFloat = 24
    /// Use `Capsule()` directly wherever the shape is a simple rectangle — this
    /// exists only for the rare case a `RoundedRectangle` needs a fully-pill radius.
    static let pill: CGFloat = 999
}

/// Semantic text styles, all built on SwiftUI's built-in Dynamic-Type-aware system
/// styles (`.headline`, `.title2`, ...) rather than fixed point sizes — iPad gets
/// more layout space and larger imagery through `AppMetrics`, not dramatically
/// larger type, matching Apple's own hierarchy instead of an invented scale.
enum AppTypography {
    static let displayXL: Font = .largeTitle
    static let navigationTitle: Font = .headline.weight(.semibold)
    static let pageTitle: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .title3.weight(.semibold)
    static let cardTitle: Font = .headline.weight(.semibold)
    static let body: Font = .body
    static let metadata: Font = .subheadline
    static let smallMetadata: Font = .footnote
    static let button: Font = .headline.weight(.semibold)
    static let tabLabel: Font = .caption.weight(.medium)
    static let sidebarItem: Font = .body
}

/// Responsive sizing driven by horizontal size class, not specific device names —
/// so this reads correctly in Split View/Slide Over too, not just full-screen iPad.
/// Own one `AppMetrics(horizontalSizeClass:)` per screen (from
/// `@Environment(\.horizontalSizeClass)`) instead of each view re-deriving its own
/// `isRegular` bool and inline breakpoint numbers.
struct AppMetrics {
    let horizontalSizeClass: UserInterfaceSizeClass?

    var isRegular: Bool { horizontalSizeClass == .regular }

    var screenPadding: CGFloat { isRegular ? AppSpacing.xxl : AppSpacing.lg }
    var sectionGap: CGFloat { isRegular ? AppSpacing.xxl : AppSpacing.xl }
    var cardPadding: CGFloat { isRegular ? AppSpacing.lg : AppSpacing.md }
    var cardRadius: CGFloat { isRegular ? 20 : AppRadius.card }

    var mealImageSize: CGFloat { isRegular ? 104 : 88 }
    var chatThumbnailSize: CGFloat { isRegular ? 40 : 36 }
    var imageRadius: CGFloat { AppRadius.image }

    var dayChipWidth: CGFloat { isRegular ? 72 : 64 }
    var dayChipHeight: CGFloat { isRegular ? 60 : 56 }
    var dayChipGap: CGFloat { isRegular ? 10 : AppSpacing.xs }
    var dayChipRadius: CGFloat { 16 }

    var groceryRowMinHeight: CGFloat { 52 }
    var textInputHeight: CGFloat { 52 }
    var primaryButtonHeight: CGFloat { 52 }
    var minimumTapTarget: CGFloat { 44 }

    var sidebarIconSize: CGFloat { 20 }
    var sidebarRowHeight: CGFloat { 48 }

    /// Content stays readable instead of stretching edge-to-edge in iPad's much
    /// wider detail column — each screen picks whichever cap fits its own content
    /// shape (Groceries deliberately has none: it's list/table-like and should use
    /// the column's real width).
    var chatContentMaxWidth: CGFloat { 780 }
    var mealPlanContentMaxWidth: CGFloat { 720 }
    var recipeContentMaxWidth: CGFloat { 760 }
    var formContentMaxWidth: CGFloat { 640 }
}
