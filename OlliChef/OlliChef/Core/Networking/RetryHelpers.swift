import Foundation
import FirebaseAuth

enum RetryHelpers {
    /// Mirrors networkUtils.ts's retryRequest: linear backoff (delay * attempt),
    /// never retries a 4xx response.
    static func retryRequest<T>(
        maxRetries: Int = NetworkConfig.retryAttempts,
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error!
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if case APIClientError.httpError(let statusCode, _) = error,
                   (400..<500).contains(statusCode) {
                    throw error
                }
                if attempt < maxRetries {
                    let delay = NetworkConfig.retryDelay * Double(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    /// Mirrors networkUtils.ts's retryWithBackoff: exponential backoff, but only for
    /// Firebase Auth's network-request-failed error — everything else fails immediately.
    static func retryWithBackoff<T>(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error!
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt == maxRetries - 1 {
                    throw error
                }
                let nsError = error as NSError
                guard nsError.domain == AuthErrorDomain,
                      nsError.code == AuthErrorCode.networkError.rawValue else {
                    throw error
                }
                let delay = baseDelay * pow(2, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError
    }
}
