import FirebaseAuth

enum FirebaseTokenProviderError: Error {
    case signInRequired
}

/// Mirrors networkUtils.ts's attachFirebaseIdToken: fetches the current user's ID token,
/// retrying once with a forced refresh if the cached token fails to resolve.
enum FirebaseTokenProvider {
    static func idToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw FirebaseTokenProviderError.signInRequired
        }
        do {
            return try await user.getIDToken(forcingRefresh: forceRefresh)
        } catch {
            return try await user.getIDToken(forcingRefresh: true)
        }
    }
}
