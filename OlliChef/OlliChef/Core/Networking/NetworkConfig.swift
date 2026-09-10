import Foundation

enum NetworkConfig {
    static let timeout: TimeInterval = 30
    static let retryAttempts = 3
    static let retryDelay: TimeInterval = 1.0
}

let offlineMessage = "No internet connection. Please check your network and try again."
