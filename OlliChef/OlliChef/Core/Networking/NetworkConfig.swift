import Foundation

/// Plain constants with no actor affinity — exempted from the project's default
/// MainActor isolation so they stay readable from background contexts like
/// RetryHelpers' network retry logic, which must not be pinned to the main actor.
nonisolated enum NetworkConfig {
    static let timeout: TimeInterval = 30
    static let retryAttempts = 3
    static let retryDelay: TimeInterval = 1.0
    static let offlineMessage = "No internet connection. Please check your network and try again."
}
