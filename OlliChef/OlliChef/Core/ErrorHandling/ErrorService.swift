import FirebaseCrashlytics
import Foundation

/// Mirrors ErrorService.ts: all errors are logged via Crashlytics, with the same
/// attribute shape (error_type, screen, timestamp, meta) so dashboards stay comparable.
enum ErrorService {
    static func initializeCrashlytics() {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCrashlyticsCollectionEnabled(true)
        crashlytics.setCustomValue("iOS", forKey: "platform")
        #if DEBUG
        crashlytics.setCustomValue("development", forKey: "environment")
        #else
        crashlytics.setCustomValue("production", forKey: "environment")
        #endif
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            crashlytics.setCustomValue(version, forKey: "app_version")
        }
        crashlytics.setCustomValue(ISO8601DateFormatter().string(from: Date()), forKey: "initialized_at")
    }

    static func logError(type: String, message: String, meta: [String: String] = [:], screen: String) {
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(type, forKey: "error_type")
        crashlytics.setCustomValue(screen, forKey: "screen")
        crashlytics.setCustomValue(ISO8601DateFormatter().string(from: Date()), forKey: "timestamp")
        for (key, value) in meta {
            crashlytics.setCustomValue(value, forKey: key)
        }
        crashlytics.log("[\(type)] \(message)")
        crashlytics.record(error: NSError(
            domain: type,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
    }
}
