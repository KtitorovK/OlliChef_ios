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

struct RootView: View {
    @StateObject private var authState = AuthState()
    @AppStorage("onboarding.completed") private var onboardingComplete = false

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
                NavigationStack {
                    MainTabView()
                        .navigationTitle("OlliChef")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink(value: ProfileRoute()) {
                                    Image(systemName: "person.crop.circle")
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
        .environmentObject(authState)
    }
}

/// A marker type for routing to UserProfile via `NavigationLink(value:)`.
struct ProfileRoute: Hashable {}
