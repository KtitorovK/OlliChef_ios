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

/// DEV SWITCH — set to `false` before testing the paywall/purchase flow with a
/// sandbox account, and before any TestFlight/App Store build. While `true`, the
/// subscription gate is skipped entirely so the rest of the app can be tested without
/// completing a purchase every time.
let bypassPaywallForTesting = true

struct RootView: View {
    @StateObject private var authState = AuthState()
    @StateObject private var subscriptionState = SubscriptionState()
    @AppStorage("onboarding.completed") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                    .tint(AppColor.brandPrimary)
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
        .task(id: authState.user?.uid) {
            await subscriptionState.start(for: authState.user?.uid)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await subscriptionState.handleAppForeground() }
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
                .tint(AppColor.brandPrimary)
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
                    .navigationTitle(horizontalSizeClass == .regular ? "" : "OlliChef")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if horizontalSizeClass != .regular {
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
            }
            .tint(AppColor.brandPrimary)
        }
    }
}

/// A marker type for routing to UserProfile via `NavigationLink(value:)`.
struct ProfileRoute: Hashable {}
