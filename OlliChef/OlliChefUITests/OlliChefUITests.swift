//
//  OlliChefUITests.swift
//  OlliChefUITests
//
//  Created by Константин Ктиторов on 10. 9. 2026..
//

import XCTest

/// Smoke coverage for the golden path this app can actually reach without a real Apple ID:
/// cold launch → onboarding → auth. Sign in with Apple itself can't be driven from XCUITest
/// (there's no way to authenticate a real Apple ID from CI), so authenticated screens (Chat,
/// Meal Plan, Groceries) aren't covered here — that gap is real, not an oversight. §9 of the
/// roadmap's own testing plan calls for pre-authenticated launches via an injected E2E
/// session from a test backend; that backend endpoint doesn't exist yet, so this suite covers
/// only what's reachable today. Every lookup below uses `.accessibilityIdentifier`, per that
/// same section's "never a text-based lookup" rule — a copy change should never break this.
final class OlliChefUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Mirrors AppDelegate's resetStateForUITestingIfNeeded: guarantees a clean
        // "never onboarded" state every run, regardless of what a prior test left behind.
        app.launchArguments = ["-uiTesting"]
    }

    override func tearDownWithError() throws {
        // Explicit teardown rather than leaving the prior test's instance running until
        // the next `launch()` implicitly kills it — cuts down on cross-test resource
        // buildup within one long automation session.
        app.terminate()
    }

    @MainActor
    func testColdLaunchReachesOnboarding() throws {
        app.launch()

        XCTAssertTrue(app.staticTexts["onboarding.headline"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["onboarding.skip"].exists)
        XCTAssertTrue(app.buttons["onboarding.continue"].exists)
    }

    @MainActor
    func testSkippingOnboardingReachesAuthScreen() throws {
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 60))
        app.buttons["onboarding.skip"].tap()

        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["auth.tagline"].waitForExistence(timeout: 60))
    }

    @MainActor
    func testOnboardingSlidesAdvanceToGetStarted() throws {
        app.launch()

        let continueButton = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 60))
        // 4 slides total: 3 taps land on the last one, where the same identifier's
        // label relabels from "Next" to "Get Started".
        continueButton.tap()
        continueButton.tap()
        continueButton.tap()
        continueButton.tap()

        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 60))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
