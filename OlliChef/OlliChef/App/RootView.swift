import FirebaseAuth
import SwiftUI

/// Mirrors App.tsx's AppContent gating order: onboarding is checked before auth and
/// takes priority over it — a signed-in user who hasn't onboarded still sees
/// onboarding first. `phase` is a plain computed property over directly-observed
/// state (@StateObject / @AppStorage), so SwiftUI's own observation re-evaluates it
/// automatically — no separate Combine pipeline needed.
enum SessionPhase {
    case loading
    case onboarding
    case auth
    case main
}

/// DEV SWITCH — flip to `true` locally while testing other screens without
/// completing a purchase every time. Gated behind `#if DEBUG` so a Release/Archive
/// build (App Store, TestFlight) always compiles this to `false` regardless of what's
/// checked in — the subscription gate can no longer ship disabled by accident.
#if DEBUG
let bypassPaywallForTesting = false
#else
let bypassPaywallForTesting = false
#endif

struct RootView: View {
    @StateObject private var authState = AuthState()
    @StateObject private var subscriptionState = SubscriptionState()
    // Owned here rather than inside MainTabView so it's in scope for UserProfileScreen
    // too: on iPhone, Profile is pushed via a navigationDestination attached to this
    // same outer NavigationStack — a sibling of MainTabView, not a descendant — so an
    // environmentObject set only inside MainTabView's own body never reaches it there
    // (iPad's fullScreenCover path happened to work either way, since covers inherit
    // the presenting view's environment).
    @StateObject private var tabRouter = TabRouter()
    @AppStorage("onboarding.completed") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingClearMealPlanConfirm = false

    private var phase: SessionPhase {
        guard authState.isInitialized else { return .loading }
        if !onboardingComplete { return .onboarding }
        return authState.user != nil ? .main : .auth
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(AppColor.brandAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.surfaceBody)

            case .onboarding:
                OnboardingScreen(onComplete: { onboardingComplete = true })

            case .auth:
                AuthScreen()

            case .main:
                mainContent
            }
        }
        .environmentObject(authState)
        .environmentObject(subscriptionState)
        .environmentObject(tabRouter)
        .task(id: authState.user?.uid) {
            await subscriptionState.start(for: authState.user?.uid)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await subscriptionState.handleAppForeground() }
                // Retries Remote Config if launch never got a live fetch (e.g. no
                // network at cold start) or it's been over an hour — silent by design,
                // since "still offline" on a background retry isn't an actionable
                // error the way a first-ever launch failure is (see AppDelegate).
                Task { try? await PromptManager.shared.refreshIfNeeded() }
            }
        }
    }

    /// Mirrors SubscriptionAwareNavigator: a full-screen loading state while the first
    /// entitlement check is in flight, then either the paywall or the real app — never
    /// both, and never a dismissible sheet over the tabs.
    @ViewBuilder
    private var mainContent: some View {
        if subscriptionState.isLoading {
            ProgressView()
                .tint(AppColor.brandAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.surfaceBody)
        } else if !subscriptionState.hasAccess && !bypassPaywallForTesting {
            PaywallScreen()
        } else {
            // On iPad (regular width), MainTabView renders its own NavigationSplitView
            // with its own inner NavigationStack, toolbar, and navigationDestinations
            // scoped to the detail column — this outer stack's title/toolbar are
            // suppressed there to avoid a second, redundant profile button; the
            // destinations stay harmlessly declared either way; iPad's inner stack
            // intercepts first, iPhone's plain TabView relies on this outer one exactly
            // as before.
            NavigationStack {
                MainTabView()
                    // Was always "OlliChef" on iPhone regardless of tab; the nav bar
                    // now reflects whichever screen is actually showing, matching how
                    // iPad's own sidebar detail column already titles itself.
                    .navigationTitle(horizontalSizeClass == .regular ? "" : tabRouter.selection.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if horizontalSizeClass != .regular {
                            if tabRouter.selection == .mealPlan, tabRouter.hasMealPlan {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        showingClearMealPlanConfirm = true
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                    }
                                }
                            }
                            if tabRouter.selection == .groceries, let shareText = tabRouter.groceryShareText {
                                ToolbarItem(placement: .topBarTrailing) {
                                    ShareLink(item: shareText) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink(value: ProfileRoute()) {
                                    Image("IconProfile")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: Meal.self) { meal in
                        RecipeStoryScreen(meal: meal)
                    }
                    .navigationDestination(for: ProfileRoute.self) { _ in
                        UserProfileScreen()
                    }
                    .alert("Clear Current Meal Plan", isPresented: $showingClearMealPlanConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear", role: .destructive) { tabRouter.requestMealPlanClear = Date() }
                    } message: {
                        Text("Are you sure you want to clear the current meal plan?")
                    }
            }
            .tint(AppColor.brandAction)
        }
    }
}

/// A marker type for routing to UserProfile via `NavigationLink(value:)`.
struct ProfileRoute: Hashable {}
