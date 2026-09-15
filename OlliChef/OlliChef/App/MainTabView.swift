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
/// has plenty of. The detail column owns its own `NavigationStack` + toolbar +
/// navigationDestinations so pushes (a meal → its recipe, the profile icon) stay scoped
/// to that column and the sidebar stays visible — mirrors RootView's outer stack
/// deliberately rather than sharing it, since two competing `NavigationLink` targets
/// across a `NavigationSplitView` boundary is exactly the kind of ambiguity that broke
/// hit-testing the last time this app nested stacks carelessly.
private struct MainSplitView: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var authState: AuthState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingProfile = false

    /// iOS's `List(selection:)` needs an optional binding (unlike macOS's non-optional
    /// overload); nil sets are ignored since some section should always stay selected.
    private var sidebarSelection: Binding<MainTab?> {
        Binding(get: { router.selection }, set: { if let newValue = $0 { router.selection = newValue } })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                detailView
                    .navigationTitle(router.selection.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: Meal.self) { meal in
                        RecipeStoryScreen(meal: meal)
                    }
            }
        }
        .tint(AppColor.brandPrimary)
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                UserProfileScreen()
                    .toolbar {
                        // An iPad sheet has no swipe-down affordance like iPhone's grabber —
                        // without an explicit close control there's no way to dismiss it.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingProfile = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }
            }
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
            showingProfile = true
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
    /// every single tap. All three stay mounted permanently instead; only visibility and
    /// hit-testing switch, so a screen's state and its already-loaded data persist exactly
    /// like the iPhone tab bar's.
    private var detailView: some View {
        ZStack {
            ChatScreen()
                .opacity(router.selection == .chat ? 1 : 0)
                .allowsHitTesting(router.selection == .chat)
                .accessibilityHidden(router.selection != .chat)
            MealPlanScreen()
                .opacity(router.selection == .mealPlan ? 1 : 0)
                .allowsHitTesting(router.selection == .mealPlan)
                .accessibilityHidden(router.selection != .mealPlan)
            GroceryListScreen()
                .opacity(router.selection == .groceries ? 1 : 0)
                .allowsHitTesting(router.selection == .groceries)
                .accessibilityHidden(router.selection != .groceries)
        }
    }
}
