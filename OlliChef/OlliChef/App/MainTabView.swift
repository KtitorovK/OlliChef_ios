import FirebaseAuth
import SwiftUI

/// Adaptive by size class: a bottom `TabView` on iPhone (compact width) — mirroring
/// AppNavigator.tsx's TabNavigator exactly, same as before — and a `NavigationSplitView`
/// sidebar on iPad (regular width), which RN never had (confirmed: RN's own tablet
/// handling is cosmetic only — bigger fonts/padding, never a structural layout change).
/// Both branches share one `TabRouter` so cross-screen navigation (e.g. switching to
/// Meal Plan after accepting a plan) works identically either way, and so a live size
/// class change (iPad Split View / Slide Over multitasking) doesn't reset the selection.
struct MainTabView: View {
    @StateObject private var router = TabRouter()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                MainSplitView()
            } else {
                MainTabBarView()
            }
        }
        .environmentObject(router)
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
        .tint(AppColor.brandPrimary)
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // Every push mechanism tried here — NavigationPath.append, navigationDestination(item:),
    // navigationDestination(isPresented:), even the legacy NavigationLink(isActive:) — silently
    // no-ops inside this NavigationSplitView's detail column on this Xcode 26.4/iOS 26.4 SDK,
    // confirmed live with a visible tap counter: the bound state updates every time, but no
    // push ever renders. A fullScreenCover sidesteps NavigationStack's push machinery entirely
    // (it's a plain modal presentation), so it isn't affected by whatever the underlying bug is.
    @State private var selectedMeal: Meal?
    @State private var isShowingProfile = false

    /// iOS's `List(selection:)` needs an optional binding (unlike macOS's non-optional
    /// overload); nil sets are ignored since some section should always stay selected.
    private var sidebarSelection: Binding<MainTab?> {
        Binding(get: { router.selection }, set: { if let newValue = $0 { router.selection = newValue } })
    }

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
        }
        .tint(AppColor.brandPrimary)
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
            .tint(AppColor.brandPrimary)
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
            .tint(AppColor.brandPrimary)
        }
    }

    /// The three nav rows never fill a full-height iPad sidebar on their own — rather
    /// than leaving that space bare, a brand header grounds the top and an
    /// account row (mirroring Settings.app's own sidebar pattern) anchors the bottom,
    /// which also gives Profile a permanent, single home instead of a toolbar button
    /// that would otherwise have to be duplicated onto every detail screen.
    private var sidebar: some View {
        List(MainTab.allCases, selection: sidebarSelection) { tab in
            Label(tab.title, image: tab.iconName)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            sidebarHeader
        }
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image("AppLogoMark")
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("OlliChef")
                .font(AppTypography.headline.weight(.bold))
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var accountRow: some View {
        Button {
            isShowingProfile = true
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColor.brandPrimary)
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
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColor.border).frame(height: 0.5)
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
        TabView(selection: $router.selection) {
            ChatScreen().tag(MainTab.chat)
            MealPlanScreen().tag(MainTab.mealPlan)
            GroceryListScreen().tag(MainTab.groceries)
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
