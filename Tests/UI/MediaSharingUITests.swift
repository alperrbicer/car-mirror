import XCTest

final class MediaSharingUITests: XCTestCase {
    func testHomeTVAndCarPlayOpenDistinctDestinations() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["page-mirror"].tap()
        reveal(app.buttons["home-carplay"], app: app)
        app.buttons["home-carplay"].tap()
        let carPlay = app.buttons["guide-CarPlay"]
        XCTAssertTrue(carPlay.waitForExistence(timeout: 5))
        XCTAssertTrue(carPlay.isSelected)
        XCTAssertFalse(app.buttons["connection-scan-cast"].exists)
        app.buttons["close-connection-guide"].tap()
        app.buttons["tv-connection"].tap()
        XCTAssertTrue(app.buttons["connection-scan-cast"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["guide-CarPlay"].exists)
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.buttons["home-carplay"].waitForExistence(timeout: 5))
    }

    func testQuickLinkPreservesURLWhenMembershipClosed() {
        let app = launch(playbackAccess: false)
        reveal(app.buttons["share-link"], app: app)
        app.buttons["share-link"].tap()
        let field = app.textFields["quick-media-url"]
        guard field.waitForExistence(timeout: 5) else { XCTFail("The link form did not open"); return }
        let address = "https://example.com/video.mp4"
        field.tap(); field.typeText(address)
        app.buttons["quick-media-play"].tap()
        let close = app.buttons["pro-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, address)
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("sharing-link-membership-preserves-input", app: app)
    }

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
        XCTAssertTrue(app.descendants(matching: .any)["connection-airplay"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connection-scan-cast"].exists)
        capture("sharing-direct-connections", app: app)
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
        guard app.otherElements["player-video"].waitForExistence(timeout: 20) else {
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
        let airplay = app.descendants(matching: .any)["connection-airplay"].firstMatch
        XCTAssertTrue(airplay.waitForExistence(timeout: 5))
        XCTAssertTrue(airplay.isHittable)
        capture("sharing-guide-large-type", app: app)
    }

    func testVehiclePhoneHandoffFavoritesAndCompactPlayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-playback-access", "-mirivo-ui-carplay", "-mirivo-ui-carplay-display",
                               "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tv-route-status"].waitForExistence(timeout: 15))
        app.buttons["tv-route-status"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["connection-airplay"].firstMatch.waitForExistence(timeout: 5))
        capture("vehicle-connections", app: app)
        app.buttons["Kapat"].tap()
        reveal(app.buttons["share-link"], app: app)
        app.buttons["share-link"].tap()
        let address = app.textFields["quick-media-url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap(); address.typeText("http://127.0.0.1:18779/Kiyi-Hikayeleri-S01-E01.mp4")
        app.buttons["quick-media-play"].tap()
        let phone = app.buttons["player-play-on-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        let transport = app.buttons["player-play-pause"]
        XCTAssertTrue(transport.waitForExistence(timeout: 5))
        let playing = NSPredicate(format: "label == %@", "Duraklat")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: transport)], timeout: 15), .completed)
        transport.tap()
        let paused = NSPredicate(format: "label == %@", "Oynat")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: paused, object: transport)], timeout: 5), .completed)
        let heart = app.buttons["player-favorite"]
        heart.tap()
        XCTAssertEqual(heart.label, "Favorilerden çıkar")
        capture("vehicle-phone-remote", app: app)
        phone.tap()
        XCTAssertTrue(phone.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player-play-pause"].label, "Oynat", "Moving the video must preserve pause")
        XCTAssertTrue(app.buttons["player-fullscreen"].exists)
        capture("vehicle-phone-local", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let mini = app.buttons["now-playing-open"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["now-playing-play-pause"].isHittable)
        XCTAssertTrue(app.buttons["now-playing-stop"].isHittable)
        capture("vehicle-mini-player", app: app)
        app.buttons["page-library"].tap()
        app.buttons["open-favorites"].tap()
        XCTAssertTrue(app.buttons["player-favorite"].waitForExistence(timeout: 5))
        capture("vehicle-favorites", app: app)
    }

    private func launch(large: Bool = false, playbackAccess: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        if playbackAccess { app.launchArguments.append("-mirivo-ui-playback-access") }
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
        let screenshot = app.screenshot()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-" + name + ".png")
        try? screenshot.pngRepresentation.write(to: file)
        print("MIRIVO_UI_CAPTURE: \(file.path)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
