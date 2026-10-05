import XCTest

final class AppServicesUITests: XCTestCase {
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
