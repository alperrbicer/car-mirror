import XCTest

final class AppServicesUITests: XCTestCase {
    func testMeasurementChoicesDefaultOffAndReviewLinkIsAvailableWithoutFirebase() {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)",
                               "-analytics.enabled", "NO", "-diagnostics.crashReports.enabled", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["open-settings"].tap()
        let analytics = app.switches["settings-analytics"]
        for _ in 0..<6 where !analytics.isHittable { app.swipeUp() }
        XCTAssertEqual(analytics.value as? String, "0")
        XCTAssertFalse(analytics.isEnabled)
        let crashes = app.switches["settings-crash-reports"]
        for _ in 0..<4 where !crashes.isHittable { app.swipeUp() }
        XCTAssertEqual(crashes.value as? String, "0")
        XCTAssertFalse(crashes.isEnabled)
        let review = app.descendants(matching: .any)["settings-rate-app"].firstMatch
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable)
        XCTAssertEqual(app.alerts.count, 0)
        keepScreenshot(app, name: "Measurement consent and App Store review - Turkish")
    }
    func testRequiredUpdateReplacesNavigationAndCannotBeDismissed() {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-required-update", "-AppleLanguages", "(tr)"]
        app.launch()
        XCTAssertTrue(app.buttons["required-update-store"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["required-update-retry"].exists)
        XCTAssertFalse(app.buttons["open-settings"].exists)
        app.swipeDown()
        XCTAssertTrue(app.buttons["required-update-store"].exists)
        app.buttons["required-update-retry"].tap()
        XCTAssertTrue(app.buttons["required-update-store"].exists)
        keepScreenshot(app, name: "Required update - Turkish")
    }
    func testNotificationsAreUnavailableWithoutFirebaseAndDoNotPromptOnLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["settings-notifications"].waitForExistence(timeout: 5))
        app.buttons["settings-notifications"].tap()
        XCTAssertTrue(app.switches["notifications-enabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["notifications-enabled"].isEnabled)
        let reminder = app.switches["car-connection-reminder-enabled"]
        XCTAssertTrue(reminder.exists)
        XCTAssertTrue(reminder.isEnabled, "Local reminders must work without Firebase")
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
        keepScreenshot(app, name: "Notification settings - Turkish")
    }
    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
