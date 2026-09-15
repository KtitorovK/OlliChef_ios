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
