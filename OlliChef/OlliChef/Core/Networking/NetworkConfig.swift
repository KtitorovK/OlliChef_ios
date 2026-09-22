import Foundation

/// Plain constants with no actor affinity — exempted from the project's default
/// MainActor isolation so they stay readable from background contexts like
/// RetryHelpers' network retry logic, which must not be pinned to the main actor.
nonisolated enum NetworkConfig {
    static let timeout: TimeInterval = 30
    // Chat send can ask for a lot in one turn (e.g. "add meals for the rest of the
    // week") — generating that legitimately took longer than the default 30s budget,
    // and the automatic retry firing on a request that was actually still succeeding
    // server-side caused a same-conversation collision (seen live as an HTTP 400 right
    // after the timeout). A longer budget here lets the real response land normally.
    static let chatSendTimeout: TimeInterval = 120
    static let retryAttempts = 3
    static let retryDelay: TimeInterval = 1.0
    static let offlineMessage = "No internet connection. Please check your network and try again."
}
