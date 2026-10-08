import XCTest

final class MediaSharingUITests: XCTestCase {
    func testQuickLinkValidationAndConnectionGuide() {
        let app = launch()
        capture("sharing-overview", app: app)
        reveal(app.buttons["share-link"], app: app)
        capture("sharing-home", app: app)
        app.buttons["share-link"].tap()
        let field = app.textFields["quick-media-url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quick-media-play"].isEnabled)
        field.tap(); field.typeText("file:///private/test.mp4")
        XCTAssertTrue(app.staticTexts["quick-media-error"].exists)
        XCTAssertFalse(app.buttons["quick-media-play"].isEnabled)
        capture("sharing-invalid-link", app: app)
        app.buttons["Kapat"].tap()
        reveal(app.buttons["connection-guide"], app: app)
        app.buttons["connection-guide"].tap()
        XCTAssertTrue(app.buttons["guide-Google Cast"].waitForExistence(timeout: 5))
        app.buttons["guide-AirPlay"].tap()
        XCTAssertTrue(app.buttons["guide-AirPlay"].isSelected)
        capture("sharing-airplay-guide", app: app)
        XCTAssertFalse(app.buttons["guide-CarPlay"].exists)
    }

    func testPhotoPickerCancelReturnsToHub() {
        let app = launch()
        reveal(app.buttons["share-photos"], app: app)
        app.buttons["share-photos"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        capture("sharing-system-photo-picker", app: app)
        cancel.tap()
        XCTAssertTrue(app.buttons["share-photos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["start-slideshow"].exists)
    }

    func testSelectedPhotosOpenEditorAndPlaySlideshow() throws {
        let app = launch()
        try selectTwoPhotos(app)
        XCTAssertTrue(app.buttons["start-slideshow"].waitForExistence(timeout: 15))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.buttons["share-photos"].waitForExistence(timeout: 5))
        // Closing an edit session must release only that session's files.
        try selectTwoPhotos(app)
        let start = app.buttons["start-slideshow"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["2 fotoğraf"].exists)
        capture("sharing-slideshow-editor", app: app)
        start.tap()
        guard app.navigationBars["Oynatıcı"].waitForExistence(timeout: 20) else {
            XCTFail("The selected photos did not reach the player"); return
        }
        let pause = app.buttons["Duraklat"].firstMatch
        guard pause.waitForExistence(timeout: 8) else { XCTFail("The slideshow did not start playing"); return }
        pause.tap()
        capture("sharing-slideshow-playing", app: app)
    }

    private func selectTwoPhotos(_ app: XCUIApplication) throws {
        reveal(app.buttons["share-photos"], app: app)
        app.buttons["share-photos"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        try XCTSkipUnless(photos.count >= 2, "Requires the simulator's sample photo library")
        // PhotosUI exposes its canvas thumbnails as images without XCTest hit points.
        photos.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Bitti"].isEnabled)
        photos.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Bitti"].tap()
    }

    func testLargeTypeSharingAndGuideRemainReachable() {
        let app = launch(large: true)
        reveal(app.buttons["share-link"], app: app)
        XCTAssertTrue(app.buttons["share-link"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["share-link"].frame.height, 58)
        capture("sharing-large-type", app: app)
        reveal(app.buttons["connection-guide"], app: app)
        app.buttons["connection-guide"].tap()
        XCTAssertTrue(app.buttons["guide-AirPlay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guide-AirPlay"].isHittable)
        app.buttons["guide-AirPlay"].tap()
        capture("sharing-guide-large-type", app: app)
    }

    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
