import SwiftUI

/// Mirrors App.tsx's AppContent: a NavigationStack wraps the whole main-app case so
/// RecipeStory and UserProfile push over the entire tab bar (full-screen, tabs hidden)
/// exactly like the RN root Stack.Navigator, rather than nesting inside one tab's stack.
struct RootView: View {
    @StateObject private var session = SessionState()

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
                    .tint(AppColor.brandPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColor.surfaceBody)

            case .onboarding:
                OnboardingScreen(onComplete: session.completeOnboarding)

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
    }
}

/// A marker type for routing to UserProfile via `NavigationLink(value:)`.
struct ProfileRoute: Hashable {}
