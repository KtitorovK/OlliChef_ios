import Foundation

/// Mirrors errorHandler.ts's context parameter — pass whatever's known at the call site.
struct ErrorContext {
    var location: String = "Unknown"
    var action: String?
    var errorCode: String?
    var errorMessage: String?
}

/// Mirrors errorHandler.ts's handleError: every catch block touching an external
/// service should call this so it lands in Crashlytics with consistent shape.
func handleError(_ error: Error, context: ErrorContext = ErrorContext()) {
    var meta: [String: String] = [:]
    if let action = context.action { meta["action"] = action }
    if let code = context.errorCode { meta["errorCode"] = code }
    if let message = context.errorMessage { meta["errorMessage"] = message }
    meta["error"] = String(describing: error)

    ErrorService.logError(
        type: String(describing: type(of: error)),
        message: error.localizedDescription,
        meta: meta,
        screen: context.location
    )
}
