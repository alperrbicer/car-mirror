import XCTest

/// Run the artwork fixture server with MIRIVO_FIXTURE_PORT=8774.
final class LibraryArtworkUITests: XCTestCase {
    func testSeriesSeasonsSortAndKeepPlaybackQueueWithinSeries() {
        let app = openCatalog()
        defer { app.terminate() }
        openSeriesCategory(app)
        XCTAssertTrue(app.buttons["series-open-Kıyı Hikâyeleri"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["series-open-Gece Vardiyası"].exists)
        XCTAssertFalse(app.buttons["Kıyı Hikâyeleri S01-E01"].exists)
        capture("series-library")
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let first = app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch
        let second = app.buttons["Kıyı Hikâyeleri S01-E02"].firstMatch
        let tenth = app.buttons["Kıyı Hikâyeleri S01-E10"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertLessThan(second.frame.minY, tenth.frame.minY)
        XCTAssertFalse(app.buttons["Kıyı Hikâyeleri S02-E01"].exists)
        capture("series-episodes")
        app.buttons["series-season-2"].tap()
        let nextSeason = app.buttons["Kıyı Hikâyeleri S02-E01"].firstMatch
        XCTAssertTrue(nextSeason.waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        capture("series-season-two")
        nextSeason.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(nextSeason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Gece Vardiyası S02-E04"].exists)
        app.buttons["series-season-1"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        capture("series-playback-queue")
    }

    func testOlderContinueWatchingArtworkAndSeriesResume() {
        let app = launchHistory()
        defer { app.terminate() }
        capture("continue-watching-artwork")
        app.buttons["continue-watching-all"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-list-open-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 5)
        capture("continue-watching-artwork-all")
        app.buttons["close-continue-watching"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-open-")).firstMatch.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let resumed = NSPredicate { _, _ in
            let value = app.sliders["Oynatma konumu"].value as? String ?? ""
            let parts = value.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 42
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: app)], timeout: 10), .completed)
        pause(app)
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["series-season-2"].exists)
        XCTAssertFalse(app.buttons["Gece Vardiyası S01-E01"].exists)
    }

    func testContinueWatchingArtworkAtAccessibilitySize() {
        let app = launchHistory(large: true)
        defer { app.terminate() }
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-open-")).firstMatch
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        if card.frame.maxY > app.frame.maxY - 80 { app.swipeUp() }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(app.staticTexts["Kıyı Hikâyeleri"].exists)
        capture("continue-watching-artwork-large")
    }

    private func launchHistory(large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-artwork-history", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["page-library"].waitForExistence(timeout: 10))
        app.buttons["page-library"].tap()
        XCTAssertTrue(app.buttons["continue-watching-all"].waitForExistence(timeout: 10))
        return app
    }

    private func openSeriesCategory(_ app: XCUIApplication) {
        let category = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DİZİ: Exxen")).firstMatch
        for _ in 0..<8 { if category.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.tap()
    }

    private func pause(_ app: XCUIApplication) {
        let button = app.buttons["player-play-pause"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if button.label == "Duraklat" { button.tap() }
    }

    func testCategoryArtworkSearchAndProviderMovieDetails() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        capture("library-artwork-categories")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FİLM: Macera")).firstMatch.tap()
        let movie = app.buttons["Mavi Yolculuk"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        capture("library-artwork-movies")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Mavi")
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Yolun Ötesi"].firstMatch.exists)
        movie.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        for _ in 0..<4 {
            if app.staticTexts["media-synopsis"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["media-synopsis"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["media-synopsis"].label.contains("İki kardeş"))
        XCTAssertTrue(app.staticTexts["2025"].exists)
        XCTAssertTrue(app.staticTexts["109 dk"].exists)
        capture("library-artwork-details")
    }

    func testSeriesGeneralAndEpisodeSynopsesFromOrdinaryM3U() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DİZİ: Exxen")).firstMatch.tap()
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let summary = app.staticTexts["media-synopsis"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Bir kıyı kasabasında"))
        capture("series-general-synopsis")
        let episode = app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch
        for _ in 0..<5 { if episode.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        for _ in 0..<6 { if summary.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Kasabaya dönen bir mektup"))
        XCTAssertFalse(app.staticTexts["media-details-empty"].exists)
        capture("series-episode-synopsis")
    }

    func testMetadataNetworkFailureOffersRetryInsteadOfClaimingNoDescription() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Diğer")).firstMatch.tap()
        app.buttons["Bilgi Bağlantısı Hatası"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let retry = app.buttons["media-details-retry"]
        for _ in 0..<6 { if retry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["media-details-error"].exists)
        XCTAssertFalse(app.staticTexts["media-details-empty"].exists)
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        capture("metadata-error-retry")
    }

    func testMissingArtworkAndDescriptionStayUsableWithLargeText() {
        let app = openCatalog(large: true)
        defer { app.terminate() }
        capture("library-artwork-large-categories")
        app.buttons["browse-all-channels"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Eksik")
        let movie = app.buttons["Eksik Görsel"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        capture("library-artwork-missing-image")
        movie.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let empty = app.staticTexts["media-details-empty"]
        for _ in 0..<8 {
            if empty.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        capture("library-artwork-missing-details")
    }

    private func openCatalog(large: Bool = false, ordinaryPlaylist: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["page-library"].waitForExistence(timeout: 10))
        app.buttons["page-library"].tap()
        let add = app.buttons["add-source"]
        for _ in 0..<4 { if add.isHittable { break }; app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.textFields["source-name"].waitForExistence(timeout: 5))
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Görsel Kitaplık")
        app.textFields["source-url"].tap()
        app.textFields["source-url"].typeText(ordinaryPlaylist ? "http://127.0.0.1:8774/catalog.m3u" : "http://127.0.0.1:8774/catalog/get.php?username=artwork&password=fixture&type=m3u_plus")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Görsel Kitaplık", "Oynatma listesi")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        for _ in 0..<4 { if source.isHittable { break }; app.swipeUp() }
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["browse-all-channels"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let screenshot = XCUIScreen.main.screenshot()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-\(name).png")
        try? screenshot.pngRepresentation.write(to: file)
        print("MIRIVO_UI_CAPTURE: \(file.path)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
