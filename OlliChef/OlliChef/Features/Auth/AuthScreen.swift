import AuthenticationServices
import SwiftUI

/// Ported from AuthScreen.tsx's Apple flow (the only one this app uses — email/password
/// was already commented out in the RN source, and Google is dropped per the native
/// rewrite's Apple-only decision).
struct AuthScreen: View {
    @EnvironmentObject private var authState: AuthState
    @State private var currentNonce: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: AppSpacing.contentPadding) {
                Spacer().frame(height: 96)

                Text("OlliChef")
                    .font(AppTypography.displayXL.weight(.bold))
                    .foregroundStyle(AppColor.brandForest)
                    .accessibilityIdentifier("auth.title")

                Text("Your AI chef for easy meal planning")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityIdentifier("auth.tagline")

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTypography.smallMetadata)
                        .foregroundStyle(AppColor.statusError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.contentPadding)
                }

                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal, AppSpacing.buttonHorizontal)
                    .disabled(authState.isLoading)
            }
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Peeking in from behind the screen's own trailing edge — inset just
            // enough that his face and gripping hands stay fully on screen (a
            // positive offset here pushed him too far past the edge, cropping part
            // of him off instead of just the intended sliver at his very side).
            Image("ChefMascot")
                .resizable()
                .scaledToFit()
                .frame(height: 220)
                .offset(x: -20, y: -140)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(AppColor.surfaceBody)
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = currentNonce else {
                errorMessage = "We couldn't complete Sign in with Apple. Please try again."
                return
            }
            Task {
                do {
                    try await authState.signInWithApple(
                        idToken: idToken,
                        rawNonce: rawNonce,
                        fullName: credential.fullName
                    )
                } catch {
                    handleError(error, context: ErrorContext(location: "AuthScreen", action: "apple_sign_in"))
                    errorMessage = friendlyMessage(for: error)
                }
            }
        case .failure(let error):
            // User cancellation isn't a real error — don't surface it.
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            handleError(error, context: ErrorContext(location: "AuthScreen", action: "apple_sign_in"))
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Never show raw NSError text — the technical detail still reaches Crashlytics
    /// via handleError above; this is only what the person on screen sees.
    private func friendlyMessage(for error: Error) -> String {
        if NetworkErrorClassifier.isNetworkError(error) {
            return NetworkConfig.offlineMessage
        }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain {
            return "Sign in with Apple isn't available right now. Make sure you're signed into an Apple ID on this device, then try again."
        }
        return "Something went wrong signing you in. Please try again."
    }
}
