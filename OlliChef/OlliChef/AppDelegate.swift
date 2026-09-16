//
//  AppDelegate.swift
//  OlliChef
//

import UIKit
import FirebaseCore
import FirebaseAuth

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        ErrorService.initializeCrashlytics()
        resetStateForUITestingIfNeeded()
        // Fire-and-forget: PromptManager's accessors already fall back to safe local
        // defaults (DefaultPrompts) if this hasn't finished yet, so launch never blocks
        // on it — but without calling this at all, Remote Config is never fetched and
        // every prompt (and the ai_model parameter) silently uses the local default
        // forever. That was true here and, it turns out, in the RN app too — its own
        // initializeRemoteConfig() is exported but never called from anywhere either.
        Task {
            try? await PromptManager.shared.initialize()
        }
        return true
    }

    /// XCUITest can't drive Sign in with Apple, so a cold launch is only ever
    /// reproducible up through onboarding → auth — this just guarantees that state is
    /// clean every run. Signing out matters as much as clearing onboarding: Firebase
    /// persists a signed-in session in the Keychain, which survives app reinstalls and
    /// (on a Mac that's actually completed a real Sign in with Apple before) can already
    /// be present on a simulator that's never run this app — without this, a test that
    /// expects to land on the Auth screen instead lands on a real signed-in Chat tab.
    /// Strictly opt-in via a launch argument only the test target passes; a normal run
    /// (dev, TestFlight, App Store) never sees this argument, so this is a no-op outside
    /// of `xcodebuild test`.
    private func resetStateForUITestingIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        UserDefaults.standard.removeObject(forKey: "onboarding.completed")
        try? Auth.auth().signOut()
    }
}
