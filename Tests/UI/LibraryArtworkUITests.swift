import XCTest

/// Run the artwork fixture server with MIRIVO_FIXTURE_PORT=8774.
final class LibraryArtworkUITests: XCTestCase {
    func testCarPlayEpisodeControlsAndPictureSizing() { verifyExternalEpisodeControls(route: "carplay") }
    func testTVEpisodeControlsAndPictureSizing() { verifyExternalEpisodeControls(route: "tv") }

    private func verifyExternalEpisodeControls(route: String) {
        let app = openCatalog(ordinaryPlaylist: true, externalRoute: route)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch.tap()
        let video = app.otherElements["player-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        pause(app)
        XCTAssertFalse(app.buttons["player-large-controls"].exists)
        XCTAssertFalse(app.buttons["previous-episode"].isEnabled)
        XCTAssertTrue(app.buttons["next-episode"].isEnabled)
        XCTAssertTrue(app.buttons["skip-backward"].exists)
        XCTAssertTrue(app.buttons["skip-forward"].exists)
        capture("\(route)-episode-controls")
        app.buttons["next-episode"].tap()
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S01-E02"].waitForExistence(timeout: 10))
        pause(app)
        XCTAssertTrue(app.buttons["previous-episode"].isEnabled)
        app.buttons["previous-episode"].tap()
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S01-E01"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-display-mode"].tap()
        let modes = app.descendants(matching: .any)["player-display-mode-popover"].firstMatch
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        for title in ["Normal", "Görüntüyü sığdır", "Ekranı doldur"] { XCTAssertTrue(app.buttons[title].exists) }
        capture("\(route)-picture-size-options")
        let selectedMode = route == "carplay" ? "Ekranı doldur" : "Görüntüyü sığdır"
        app.buttons[selectedMode].tap()
        XCTAssertTrue(modes.waitForNonExistence(timeout: 5))
        app.buttons["player-display-mode"].tap()
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[selectedMode].isSelected)
        app.buttons["Normal"].tap()
        XCTAssertTrue(modes.waitForNonExistence(timeout: 5))
        app.buttons["player-display-connection"].tap()
        let connected = app.buttons["connect-another-display"].waitForExistence(timeout: 5)
        capture("\(route)-working-connection-button")
        XCTAssertTrue(connected)
        app.buttons["Kapat"].tap()
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(app.buttons["Kıyı Hikâyeleri S01-E02"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        capture("\(route)-episode-list-without-search")
    }

    func testContentDetailsOnlyOpenWithDisclosureButtonAndStartCollapsed() {
        verifyDetailsDisclosure(large: false)
    }

    func testContentDetailsDisclosureWithLargeText() {
        verifyDetailsDisclosure(large: true)
    }

    private func verifyDetailsDisclosure(large: Bool) {
        let app = openCatalog(large: large, ordinaryPlaylist: true)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let details = app.otherElements["media-details"]
        let toggle = app.buttons["media-details-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        // Loaded facts must not automatically expand the description.
        XCTAssertTrue(app.staticTexts["2024"].waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.label, "İçerik bilgileri")
        XCTAssertFalse(app.staticTexts["media-synopsis"].exists)
        let title = details.staticTexts["Kıyı Hikâyeleri"]
        XCTAssertTrue(title.exists); title.tap()
        XCTAssertEqual(toggle.label, "İçerik bilgileri")
        XCTAssertFalse(app.staticTexts["media-synopsis"].exists)
        capture("details-collapsed-\(large)")
        if !toggle.isHittable { app.swipeUp() }
        let collapsedHeight = details.frame.height
        toggle.tap()
        let summary = app.staticTexts["media-synopsis"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.hasSuffix("birlikte ortaya çıkarırlar."), "The disclosure shows the complete synopsis")
        XCTAssertEqual(toggle.label, "Bilgileri gizle")
        XCTAssertGreaterThan(details.frame.height, collapsedHeight)
        XCTAssertGreaterThanOrEqual(summary.frame.minY, toggle.frame.maxY)
        XCTAssertFalse(app.buttons["Devamını oku"].exists)
        capture("details-expanded-\(large)")
        // Tapping noninteractive text must not collapse the panel either.
        if title.isHittable { title.tap() }
        XCTAssertEqual(toggle.label, "Bilgileri gizle")
        for _ in 0..<8 { if toggle.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(toggle.isHittable); toggle.tap()
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "İçerik bilgileri")
        capture("details-collapsed-again-\(large)")
    }

    func testEpisodeSearchEmptyStateStaysBelowSeriesDetails() {
        verifyEpisodeSearchEmptyState(large: false)
    }

    func testEpisodeSearchEmptyStateWithLargeText() {
        verifyEpisodeSearchEmptyState(large: true)
    }

    private func verifyEpisodeSearchEmptyState(large: Bool) {
        let app = openCatalog(large: large)
        defer { app.terminate() }
        openSeriesCategory(app)
        let series = app.buttons["series-open-Kıyı Hikâyeleri"]
        XCTAssertTrue(series.waitForExistence(timeout: 5)); series.tap()
        let season = app.buttons["series-season-2"]
        let list = app.descendants(matching: .any)["channel-list"].firstMatch
        for _ in 0..<8 { if season.isHittable { break }; list.swipeUp() }
        XCTAssertTrue(season.isHittable); season.tap()
        let episode = app.buttons["Kıyı Hikâyeleri S02-E01"].firstMatch
        for _ in 0..<8 { if episode.isHittable { break }; list.swipeUp() }
        XCTAssertTrue(episode.isHittable); episode.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["now-playing-open"].waitForExistence(timeout: 5))

        let search = app.searchFields["channel-search-field"]
        let query = "zzzxq"
        search.tap(); search.typeText(query)
        let empty = app.descendants(matching: .any)["channel-search-empty"].firstMatch
        capture("episode-search-start-\(large)")
        for _ in 0..<8 {
            let bottom = app.buttons["now-playing-open"].frame.minY
            if empty.exists && empty.isHittable && empty.frame.maxY <= bottom { break }
            // A list's accessibility frame can extend behind its safe-area
            // inset. Keep this gesture above the mini player and keyboard.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let top = max(list.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 16
            origin.withOffset(CGVector(dx: app.frame.midX, dy: bottom - 16))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: top)))
        }
        capture("episode-search-empty-keyboard-\(large)")
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(empty.isHittable)
        XCTAssertLessThanOrEqual(empty.frame.maxY, app.buttons["now-playing-open"].frame.minY)
        for preceding in [app.otherElements["media-details"], season] where preceding.exists {
            XCTAssertFalse(empty.frame.intersects(preceding.frame))
            XCTAssertGreaterThanOrEqual(empty.frame.minY, preceding.frame.maxY)
        }
        XCTAssertFalse(episode.exists)

        app.buttons["dismiss-channel-search-keyboard"].tap()
        XCTAssertEqual(search.value as? String, query)
        capture("episode-search-empty-dismissed-\(large)")
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        XCTAssertFalse(empty.exists)
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        XCTAssertTrue(season.isSelected)
        XCTAssertFalse(app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch.exists)
    }

    func testCatalogSearchEmptyStateRestoresSeriesAndMovies() {
        let app = openCatalog()
        defer { app.terminate() }
        openSeriesCategory(app)
        let search = app.searchFields["channel-search-field"]
        let query = "zzzxq"
        search.tap(); search.typeText(query)
        let empty = app.descendants(matching: .any)["channel-search-empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isHittable)
        XCTAssertLessThanOrEqual(empty.frame.maxY, search.frame.minY)
        capture("series-search-empty")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        XCTAssertFalse(empty.exists)
        XCTAssertTrue(app.buttons["series-open-Kıyı Hikâyeleri"].exists)
        app.buttons["dismiss-channel-search-keyboard"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let category = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FİLM: Macera")).firstMatch
        for _ in 0..<5 { if category.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(category.isHittable); category.tap()
        search.tap(); search.typeText(query)
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isHittable)
        XCTAssertLessThanOrEqual(empty.frame.maxY, search.frame.minY)
        capture("movie-search-empty")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        XCTAssertFalse(empty.exists)
        XCTAssertTrue(app.buttons["Mavi Yolculuk"].firstMatch.exists)
    }

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
        openLibrary(app)
        XCTAssertTrue(app.buttons["continue-watching-all"].waitForExistence(timeout: 10))
        return app
    }

    private func openSeriesCategory(_ app: XCUIApplication) {
        let category = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "DİZİ: Exxen")).firstMatch
        for _ in 0..<8 {
            let visible = app.frame.insetBy(dx: 0, dy: 130)
            if category.isHittable && visible.contains(CGPoint(x: category.frame.midX, y: category.frame.midY)) { break }
            app.swipeUp()
        }
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        capture("category-distinct-series-posters")
        category.tap()
    }

    private func openLibrary(_ app: XCUIApplication) {
        let page = app.buttons["page-library"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            if page.isSelected { return }
            page.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: page)
            if XCTWaiter.wait(for: [selected], timeout: 2) == .completed { return }
        }
        XCTAssertTrue(page.isSelected)
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
        showDetails(in: app)
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
        verifySeriesSynopses(movieEpisodes: false)
    }

    func testSeriesGeneralAndEpisodeSynopsesFromMovieEpisodeM3U() {
        verifySeriesSynopses(movieEpisodes: true)
    }

    private func verifySeriesSynopses(movieEpisodes: Bool) {
        let app = openCatalog(ordinaryPlaylist: true, movieEpisodes: movieEpisodes)
        defer { app.terminate() }
        openSeriesCategory(app)
        let series = app.buttons["series-open-Kıyı Hikâyeleri"]
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        capture(movieEpisodes ? "series-movie-route-catalog-poster" : "series-catalog-poster")
        series.tap()
        showDetails(in: app)
        let summary = app.staticTexts["media-synopsis"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Bir kıyı kasabasında"))
        capture(movieEpisodes ? "series-movie-route-general-synopsis" : "series-general-synopsis")
        let episode = app.buttons["Kıyı Hikâyeleri S01-E01"].firstMatch
        // List can expose a button behind the bottom search inset as hittable.
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let bottom = app.searchFields["channel-search-field"].frame.minY - 12
            if episode.isHittable && episode.frame.midY > top && episode.frame.midY < bottom { break }
            app.swipeUp()
        }
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        XCTAssertLessThan(episode.frame.midY, app.searchFields["channel-search-field"].frame.minY - 12)
        episode.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        showDetails(in: app)
        for _ in 0..<6 { if summary.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("Kasabaya dönen bir mektup"))
        XCTAssertFalse(app.staticTexts["media-details-empty"].exists)
        capture(movieEpisodes ? "series-movie-route-episode-synopsis" : "series-episode-synopsis")
    }

    func testMetadataNetworkFailureOffersRetryInsteadOfClaimingNoDescription() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        app.buttons["browse-all-channels"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Bilgi Bağlantısı Hatası")
        let movie = app.buttons["Bilgi Bağlantısı Hatası"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 10))
        movie.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        showDetails(in: app)
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
        showDetails(in: app)
        let empty = app.staticTexts["media-details-empty"]
        for _ in 0..<8 {
            if empty.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        capture("library-artwork-missing-details")
    }

    private func showDetails(in app: XCUIApplication) {
        let toggle = app.buttons["media-details-toggle"]
        for _ in 0..<8 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.label == "İçerik bilgileri" { toggle.tap() }
    }

    private func openCatalog(large: Bool = false, ordinaryPlaylist: Bool = false, movieEpisodes: Bool = false, externalRoute: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        if externalRoute == "carplay" { app.launchArguments += ["-mirivo-ui-carplay", "-mirivo-ui-carplay-display"] }
        else if externalRoute == "tv" { app.launchArguments.append("-mirivo-ui-external-display") }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        openLibrary(app)
        let add = app.buttons["add-source"]
        for _ in 0..<4 { if add.isHittable { break }; app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.textFields["source-name"].waitForExistence(timeout: 5))
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Görsel Kitaplık")
        app.textFields["source-url"].tap()
        app.textFields["source-url"].typeText(movieEpisodes ? "http://127.0.0.1:8774/catalog-movie-episodes.m3u" : ordinaryPlaylist ? "http://127.0.0.1:8774/catalog.m3u" : "http://127.0.0.1:8774/catalog/get.php?username=artwork&password=fixture&type=m3u_plus")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Görsel Kitaplık", "Oynatma listesi")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        for _ in 0..<4 { if source.isHittable { break }; app.swipeUp() }
        let categories = app.buttons["browse-all-channels"]
        for _ in 0..<3 {
            if categories.exists { break }
            if source.isHittable {
                source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            }
            if categories.waitForExistence(timeout: 3) { break }
        }
        if !categories.waitForExistence(timeout: 15) { capture("catalog-open-failed") }
        XCTAssertTrue(categories.exists)
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
