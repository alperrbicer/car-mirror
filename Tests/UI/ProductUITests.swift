import XCTest

final class ProductUITests: XCTestCase {
    private func launch(language: String = "tr", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "tr" ? "tr_TR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func capture(_ name: String, app: XCUIApplication) {
        // Capture the display: application-only cropping is unreliable after rotation.
        let screenshot = XCUIScreen.main.screenshot()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-\(name).png")
        try? screenshot.pngRepresentation.write(to: file)
        print("MIRIVO_UI_CAPTURE: \(file.path)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTurkishProductAndOfflineLegalFlows() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Yansıt"].waitForExistence(timeout: 10))
        capture("01-mirivo-home-tr", app: app)
        app.tabBars.buttons["Kaynaklar"].tap()
        XCTAssertTrue(app.staticTexts["Kaynakların burada"].waitForExistence(timeout: 5))
        capture("02-mirivo-sources-tr", app: app)
        app.buttons["Kaynak ekle"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Kaynak adı"].waitForExistence(timeout: 5))
        app.textFields["Kaynak adı"].tap(); app.textFields["Kaynak adı"].typeText("QA List")
        app.textFields["Kaynak adresi"].tap(); app.textFields["Kaynak adresi"].typeText("https://example.com/list.m3u")
        capture("03-mirivo-add-source-tr", app: app)
        app.buttons["Ekle"].tap()
        XCTAssertTrue(app.staticTexts["QA List"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Ayarlar"].tap()
        capture("04-mirivo-settings-tr", app: app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Pro")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pro yakında"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Satın al")).firstMatch.exists)
        capture("05-mirivo-pro-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Gizlilik Politikası"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["Gizlilik Politikası"].waitForExistence(timeout: 10))
        capture("06-mirivo-privacy-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Kullanım Koşulları (EULA)"].tap()
        XCTAssertTrue(app.webViews.links["Apple Standart EULA ↗"].waitForExistence(timeout: 10))
        capture("07-mirivo-terms-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeUp()
        app.buttons["Yardım ve SSS"].tap()
        XCTAssertTrue(app.webViews.links["Destek için yaz ↗"].waitForExistence(timeout: 10))
        capture("08-mirivo-help-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.swipeUp()
        app.buttons["Tüm kaynakları sil"].tap()
        let confirm = app.buttons.matching(identifier: "Tüm kaynakları sil").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirm)
        confirm?.tap()
        app.tabBars.buttons["Kaynaklar"].tap()
        XCTAssertTrue(app.staticTexts["Kaynakların burada"].waitForExistence(timeout: 5))
    }
    func testEnglishLayoutAndLargeTextLandscape() {
        let app = launch(language: "en", large: true)
        XCTAssertTrue(app.tabBars.buttons["Mirror"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Share your screen"].exists)
        capture("09-mirivo-large-text-en", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: rotated, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        // A tab transition also waits for the system rotation animation to settle.
        app.tabBars.buttons["Settings"].tap()
        app.tabBars.buttons["Mirror"].tap()
        capture("10-mirivo-landscape-en", app: app)
        XCTAssertTrue(app.staticTexts["Share your screen"].isHittable, app.debugDescription)
        app.swipeUp()
        capture("11-mirivo-landscape-scrolled-en", app: app)
        XCUIDevice.shared.orientation = .portrait
    }
}
