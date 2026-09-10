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
        VStack(spacing: AppSpacing.contentPadding * 2) {
            Spacer()

            Text("OlliChef")
                .font(.system(size: AppTypography.displayXL, weight: .bold))
                .foregroundStyle(AppColor.brandSecondary)

            Text("Your AI chef for easy meal planning")
                .font(.system(size: AppTypography.body))
                .foregroundStyle(AppColor.textSecondary)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: AppTypography.caption))
                    .foregroundStyle(AppColor.statusError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.contentPadding)
            }

            SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, AppSpacing.buttonHorizontal)
                .disabled(authState.isLoading)

            Spacer().frame(height: AppSpacing.contentPadding * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                errorMessage = "Apple Sign-In failed: no identity token"
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
                    errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }
}
