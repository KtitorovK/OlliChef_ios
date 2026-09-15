import AuthenticationServices
import Combine
import FirebaseAuth
import FirebaseCrashlytics
import Foundation

/// Ported from AuthProvider.tsx: listens to Firebase Auth state, sets the Crashlytics
/// user ID, throttles the lastActive write to once per 6 hours (best-effort — a
/// failure here must never block sign-in), and exposes Sign in with Apple + sign out.
@MainActor
final class AuthState: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isInitialized = false
    @Published private(set) var isLoading = false

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var lastActiveWriteTimestamp: Date?
    private let lastActiveThrottle: TimeInterval = 6 * 60 * 60

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task { await self.handleAuthChange(firebaseUser) }
        }
    }

    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }

    private func handleAuthChange(_ firebaseUser: User?) async {
        user = firebaseUser

        if let firebaseUser {
            Crashlytics.crashlytics().setUserID(firebaseUser.uid)
            let now = Date()
            if lastActiveWriteTimestamp == nil || now.timeIntervalSince(lastActiveWriteTimestamp!) > lastActiveThrottle {
                lastActiveWriteTimestamp = now
                try? await UserProfileService.updateLastActive()
            }
        } else {
            Crashlytics.crashlytics().setUserID("")
        }

        isInitialized = true
    }

    /// `rawNonce` must be the same value passed as the SHA256 hash into the
    /// ASAuthorizationAppleIDRequest's `nonce` — Firebase compares SHA256(raw) itself.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        isLoading = true
        defer { isLoading = false }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        let result = try await Auth.auth().signIn(with: credential)
        let isNewUser = result.additionalUserInfo?.isNewUser ?? false

        let displayName: String? = {
            if let fullName, let given = fullName.givenName, let family = fullName.familyName {
                return "\(given) \(family)"
            }
            return fullName?.givenName ?? fullName?.familyName
        }()

        // Profile setup is best-effort: Firebase auth already succeeded, so a
        // Firestore failure here must never block sign-in.
        do {
            if isNewUser {
                try await UserProfileService.initializeProfile(
                    email: result.user.email ?? "",
                    displayName: displayName ?? result.user.displayName
                )
            } else {
                do {
                    try await UserProfileService.updateLastActive()
                } catch {
                    try await UserProfileService.initializeProfile(
                        email: result.user.email ?? "",
                        displayName: displayName ?? result.user.displayName
                    )
                }
            }
        } catch {
            handleError(error, context: ErrorContext(location: "AuthState", action: "handleUserProfileCreation"))
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
