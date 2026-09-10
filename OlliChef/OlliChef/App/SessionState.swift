import Combine
import Foundation

/// Mirrors App.tsx's AppContent gating order exactly: onboarding is checked before
/// auth, and takes priority over it — a signed-in user who hasn't onboarded still
/// sees onboarding first.
enum SessionPhase {
    case loading
    case onboarding
    case auth
    case main
}

@MainActor
final class SessionState: ObservableObject {
    @Published private(set) var phase: SessionPhase = .loading

    private let onboardingCompleteKey = "onboarding.completed"

    init() {
        evaluate()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingCompleteKey)
        evaluate()
    }

    /// Real Firebase Auth state listening is wired in the Auth & Onboarding phase —
    /// for now this always resolves to .auth once onboarding is done, matching the
    /// RN app's "no user" branch.
    private func evaluate() {
        let onboardingComplete = UserDefaults.standard.bool(forKey: onboardingCompleteKey)
        phase = onboardingComplete ? .auth : .onboarding
    }
}
