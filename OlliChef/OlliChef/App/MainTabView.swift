import FirebaseAuth
import SwiftUI

/// Adaptive by size class: a bottom `TabView` on iPhone (compact width) — mirroring
/// AppNavigator.tsx's TabNavigator exactly, same as before — and a `NavigationSplitView`
/// sidebar on iPad (regular width), which RN never had (confirmed: RN's own tablet
/// handling is cosmetic only — bigger fonts/padding, never a structural layout change).
/// Both branches share one `TabRouter` (now owned by RootView, so it's also in scope
/// for UserProfileScreen — see RootView's own comment) so cross-screen navigation
/// (e.g. switching to Meal Plan after accepting a plan) works identically either way,
/// and so a live size class change (iPad Split View / Slide Over multitasking) doesn't
/// reset the selection.
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            MainSplitView()
        } else {
            MainTabBarView()
        }
    }
}

private struct MainTabBarView: View {
    @EnvironmentObject private var router: TabRouter

    var body: some View {
        TabView(selection: $router.selection) {
            ChatScreen()
                .tabItem { Label(MainTab.chat.title, image: MainTab.chat.iconName) }
                .tag(MainTab.chat)

            MealPlanScreen()
                .tabItem { Label(MainTab.mealPlan.title, image: MainTab.mealPlan.iconName) }
                .tag(MainTab.mealPlan)

            GroceryListScreen()
                .tabItem { Label(MainTab.groceries.title, image: MainTab.groceries.iconName) }
                .tag(MainTab.groceries)
        }
        // Drives the selected tab's icon/label color automatically (standard TabView
        // behavior); the unselected color stays the system default secondary gray —
        // overriding that specifically would need UITabBarAppearance/UIKit interop,
        // a materially riskier change than a design-token pass, so it's left alone.
        .tint(AppColor.brandAction)
    }
}

/// The net-new iPad piece: a persistent sidebar (pointer/trackpad hover support comes
/// free from `List`/`NavigationSplitView` on iPad) plus a detail pane showing the
/// selected section full-size, rather than a bottom tab bar eating vertical space iPad
/// has plenty of. A meal or the profile icon opens as a `fullScreenCover` rather than a
/// pushed destination — see the `selectedMeal`/`isShowingProfile` comment below for why.
private struct MainSplitView: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var authState: AuthState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // Every push mechanism tried here — NavigationPath.append, navigationDestination(item:),
    // navigationDestination(isPresented:), even the legacy NavigationLink(isActive:) — silently
    // no-ops inside this NavigationSplitView's detail column on this Xcode 26.4/iOS 26.4 SDK,
    // confirmed live with a visible tap counter: the bound state updates every time, but no
    // push ever renders. A fullScreenCover sidesteps NavigationStack's push machinery entirely
    // (it's a plain modal presentation), so it isn't affected by whatever the underlying bug is.
    @State private var selectedMeal: Meal?
    @State private var isShowingProfile = false
    @State private var showingClearMealPlanConfirm = false

    private var metrics: AppMetrics { AppMetrics(horizontalSizeClass: horizontalSizeClass) }

    /// Margin between the sidebar's own edges and each row's tap area, so the
    /// selected row's tint reads as a floating pill rather than a full-bleed bar.
    private let sidebarRowMargin: CGFloat = 14
    /// Rounded-rect radius for the selected row's tint background.
    private let sidebarSelectionRadius: CGFloat = 15

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            // NavigationSplitView's detail column already manages its own navigation
            // stack — wrapping it in an explicit NavigationStack created a second,
            // nested stack whose pushes never actually reached the screen (confirmed
            // live: state updates, a hidden NavigationLink(isActive:) fires, nothing
            // renders). Attaching navigationDestination directly to the column's root
            // content, with no extra NavigationStack, is what the API expects here.
            detailView
                .navigationTitle(router.selection.title)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.mealTapAction) { meal in
                    selectedMeal = meal
                }
                .toolbar {
                    if router.selection == .mealPlan, router.hasMealPlan {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingClearMealPlanConfirm = true
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(AppColor.brandAction)
                            }
                        }
                    }
                    if router.selection == .groceries, let shareText = router.groceryShareText {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: shareText) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(AppColor.brandAction)
                            }
                        }
                    }
                }
                .alert("Clear Current Meal Plan", isPresented: $showingClearMealPlanConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) { router.requestMealPlanClear = Date() }
                } message: {
                    Text("Are you sure you want to clear the current meal plan?")
                }
        }
        .tint(AppColor.brandAction)
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(item: $selectedMeal) { meal in
            NavigationStack {
                RecipeStoryScreen(meal: meal)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                selectedMeal = nil
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                            }
                        }
                    }
            }
            .tint(AppColor.brandAction)
        }
        .fullScreenCover(isPresented: $isShowingProfile) {
            NavigationStack {
                UserProfileScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingProfile = false
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                            }
                        }
                    }
            }
            .tint(AppColor.brandAction)
        }
    }

    /// The three nav rows never fill a full-height iPad sidebar on their own — rather
    /// than leaving that space bare, a brand header grounds the top and an
    /// account row (mirroring Settings.app's own sidebar pattern) anchors the bottom,
    /// which also gives Profile a permanent, single home instead of a toolbar button
    /// that would otherwise have to be duplicated onto every detail screen.
    ///
    /// A plain scrolling stack of buttons rather than `List(selection:)` — the list's
    /// own sidebar style draws a system selection indicator (a bordered rounded rect)
    /// around the selected row that can't be suppressed, which read as a heavy,
    /// control-panel-like box. Building the rows by hand gives full control over the
    /// selected state's tint/radius with no stroke, and lets the sidebar sit on the
    /// same calm cream surface as the rest of the app instead of the system's own
    /// sidebar chrome.
    private var sidebar: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxs) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, sidebarRowMargin)
            .padding(.top, AppSpacing.xs)
        }
        .background(AppColor.surfaceBody)
        .safeAreaInset(edge: .top) {
            sidebarHeader
        }
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 260)
    }

    private func sidebarRow(_ tab: MainTab) -> some View {
        let isSelected = tab == router.selection
        return Button {
            router.selection = tab
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(tab.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.sidebarIconSize, height: metrics.sidebarIconSize)
                Text(tab.title)
                    .font(AppTypography.sidebarItem)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppColor.brandAction : AppColor.textPrimary)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: metrics.sidebarRowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: sidebarSelectionRadius, style: .continuous)
                    .fill(isSelected ? AppColor.brandTint : Color.clear)
            )
        }
        .buttonStyle(.plain)
        // No `.hoverEffect(.highlight)` here: on at least one real iPad
        // configuration it renders as a mispositioned floating capsule at the top
        // of the detail pane instead of over the actual sidebar row — a genuine
        // SwiftUI/UIKit pointer-interaction rendering bug in this
        // NavigationSplitView + custom-Button combination, not a system/device
        // setting. The stray capsule was still hit-test-linked to this button
        // (tapping it fired this same action), confirming it was this effect
        // misrendering rather than an unrelated OS overlay.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var sidebarHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            Image("AppLogoMark")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            Text("OlliChef")
                .font(AppTypography.navigationTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xxs)
    }

    private var accountRow: some View {
        Button {
            isShowingProfile = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(AppColor.brandAccent)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(accountInitial)
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(AppColor.textOnBrand)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(accountDisplayText)
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text("View Profile")
                        .font(AppTypography.smallMetadata)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppTypography.smallMetadata.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColor.divider).frame(height: 0.5)
        }
        .background(.bar)
    }

    private var accountDisplayText: String {
        authState.user?.displayName?.isEmpty == false
            ? authState.user!.displayName!
            : (authState.user?.email ?? "Account")
    }

    private var accountInitial: String {
        String(accountDisplayText.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// A `switch` here would tear down and recreate whichever screen isn't selected every
    /// time the sidebar selection changes — unlike the iPhone `TabView` above, which keeps
    /// all three tabs alive, that would reset each screen's `@StateObject` view model and
    /// re-run its `.task` load (a fresh Firestore fetch, fresh Pexels image fetches) on
    /// every single tap.
    ///
    /// First attempt was a manual `ZStack` with opacity/allowsHitTesting/zIndex toggling —
    /// looked right, but on iPad the topmost-in-z-order screen's `List`/`ScrollView` kept
    /// intercepting taps meant for whatever was underneath even while hidden, silently
    /// swallowing every attempt to open a recipe from Meal Plan (SwiftUI's `zIndex` reorders
    /// rendering, but apparently not the underlying UIScrollView hit-testing for a hidden
    /// sibling). Confirmed iPad-only: the identical tap worked immediately on iPhone's own
    /// `TabView`. Reusing that same `TabView` here — Apple's own real view-controller-backed
    /// implementation for "keep every tab alive, show one at a time" — sidesteps the bug
    /// entirely instead of re-fighting SwiftUI's hit-testing by hand; its own tab bar is
    /// hidden since the sidebar is what actually drives `router.selection` here.
    private var detailView: some View {
        // `.toolbar(.hidden, for: .tabBar)` has to be applied to each tab's own
        // content, not to the TabView container — applied to the container, iOS 26
        // still rendered the tab bar's background as a plain, empty floating
        // capsule at the top of this NavigationSplitView's detail column, with no
        // labels but otherwise fully present (confirmed by temporarily giving the
        // tabs real `.tabItem` labels: the exact same capsule lit up as
        // "Chat / Meal Plan / Groceries"). This tab bar is never meant to be seen
        // at all, since the sidebar is what actually drives `router.selection`.
        TabView(selection: $router.selection) {
            ChatScreen().tag(MainTab.chat).toolbar(.hidden, for: .tabBar)
            MealPlanScreen().tag(MainTab.mealPlan).toolbar(.hidden, for: .tabBar)
            GroceryListScreen().tag(MainTab.groceries).toolbar(.hidden, for: .tabBar)
        }
    }
}
