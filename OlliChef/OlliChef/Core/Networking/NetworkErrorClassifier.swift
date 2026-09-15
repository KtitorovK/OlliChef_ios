import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Mirrors networkUtils.ts's isNetworkError: classifies transport/offline failures
/// across URLSession, Firebase Auth, and Firestore.
enum NetworkErrorClassifier {
    static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .timedOut, .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError

        if nsError.domain == AuthErrorDomain, nsError.code == AuthErrorCode.networkError.rawValue {
            return true
        }

        if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.unavailable.rawValue {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        if message.contains("network error") ||
            message.contains("network request failed") ||
            message.contains("failed to fetch") ||
            message.contains("no internet") ||
            message.contains("econnrefused") {
            return true
        }

        return false
    }
}
