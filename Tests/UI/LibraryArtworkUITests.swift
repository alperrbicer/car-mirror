import XCTest

/// Run the artwork fixture server with MIRIVO_FIXTURE_PORT=8774.
final class LibraryArtworkUITests: XCTestCase {
    func testListAndSearchFavoritesDoNotStartPlayback() {
        let app = openCatalog(favoriteLists: true)
        defer { app.terminate() }
        for (category, title, path) in [("FİLM: Macera", "Mavi", "movie/artwork/fixture/101.mp4"),
                                         ("TR: Ulusal", "Nova", "live/artwork/fixture/1.m3u8"),
                                         ("RADYO: Müzik", "Kıyı", "radio/favorite.mp3")] {
            let categoryButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", category)).firstMatch
            for _ in 0..<6 {
                // SwiftUI can report a below-screen lazy card as hittable.
                // Bring the entire card above the floating search field first.
                if categoryButton.isHittable && app.frame.insetBy(dx: 0, dy: 140).contains(categoryButton.frame) { break }
                app.scrollViews["channel-categories"].swipeUp()
            }
            XCTAssertTrue(categoryButton.waitForExistence(timeout: 5)); categoryButton.tap()
            let heart = app.buttons["channel-favorite-http://127.0.0.1:8774/" + path]
            let isMovie = path.hasPrefix("movie/")
            if isMovie {
                XCTAssertFalse(heart.exists, "Movie rows must not include a favorite button")
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "download-")).firstMatch.exists)
            } else {
                XCTAssertTrue(heart.waitForExistence(timeout: 5))
                heart.tap(); XCTAssertTrue(heart.isSelected)
                assertNoFavoriteMenu(app)
            }
            XCTAssertFalse(app.otherElements["player-video"].exists)
            let search = app.searchFields["channel-search-field"]
            search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
                search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            search.typeText(title)
            if isMovie {
                XCTAssertFalse(heart.exists, "Movie search results must also omit the row favorite")
                XCTAssertTrue(app.buttons["Mavi Yolculuk"].firstMatch.exists)
            } else {
                XCTAssertTrue(heart.waitForExistence(timeout: 5)); XCTAssertTrue(heart.isSelected)
                heart.tap(); XCTAssertFalse(heart.isSelected)
                heart.tap(); XCTAssertTrue(heart.isSelected)
                assertNoFavoriteMenu(app)
            }
            app.buttons["dismiss-channel-search-keyboard"].tap()
            capture("favorite-list-" + title)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.terminate(); app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch(); openLibrary(app); openFavorites(app)
        for title in ["Nova TV", "Kıyı Radyo"] {
            XCTAssertTrue(app.buttons["favorite-open-" + title].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["favorite-open-Mavi Yolculuk"].exists)
        capture("favorite-list-mixed-results")
    }

    func testContinueWatchingAllFavoritesStayInSync() { verifyAllContinuationFavorites(large: false) }
    func testContinueWatchingAllFavoritesWithLargeText() { verifyAllContinuationFavorites(large: true) }

    private func verifyAllContinuationFavorites(large: Bool) {
        let app = launchHistory(large: large)
        defer { app.terminate() }
        let all = app.buttons["continue-watching-all"]
        for _ in 0..<5 { if all.isHittable { break }; app.swipeUp() }
        all.tap()
        let firstHeart = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-list-favorite-")).firstMatch
        XCTAssertTrue(firstHeart.waitForExistence(timeout: 5))
        let heartID = firstHeart.identifier
        let heart = app.buttons[heartID]
        XCTAssertFalse(heart.isSelected)
        heart.tap()
        XCTAssertTrue(heart.isSelected)
        assertNoFavoriteMenu(app)
        heart.tap(); XCTAssertFalse(heart.isSelected)
        heart.tap(); XCTAssertTrue(heart.isSelected)
        capture("favorite-all-continuation-\(large)")
        XCTAssertEqual(heart.value as? String, "Bölüm favorilerde")
        XCTAssertFalse(app.otherElements["player-video"].exists)
        app.buttons["close-continue-watching"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-favorite-")).firstMatch
        for _ in 0..<5 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isSelected)
        XCTAssertEqual(card.value as? String, "Bölüm favorilerde")
    }

    func testDownloadedItemFavoritesUseTheOriginalContentAfterRelaunch() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FİLM: Macera")).firstMatch.tap()
        let download = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "download-")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 5)); download.tap()
        XCTAssertTrue(app.images["İndirildi"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let downloads = app.buttons["offline-downloads-open"]
        for _ in 0..<5 { if downloads.isHittable { break }; app.swipeUp() }
        downloads.tap()
        let heart = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "offline-favorite-")).firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        heart.tap(); XCTAssertTrue(heart.isSelected)
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("favorite-offline-item")
        app.terminate(); app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch(); openLibrary(app)
        for _ in 0..<5 { if downloads.isHittable { break }; app.swipeUp() }
        downloads.tap()
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        XCTAssertTrue(heart.isSelected)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "offline-item-")).firstMatch
        row.swipeLeft(); app.buttons["Sil"].tap()
        XCTAssertTrue(app.staticTexts["Henüz indirilen içerik yok"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openFavorites(app)
        XCTAssertTrue(app.buttons["favorite-open-Mavi Yolculuk"].waitForExistence(timeout: 5), "Deleting the downloaded file must preserve the original content favorite")
    }

    func testSeriesAndEpisodeFavoritesPersistInMixedPosterGrid() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        openSeriesCategory(app)
        let favorite = app.buttons["series-favorite-Kıyı Hikâyeleri"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
        XCTAssertTrue(favorite.isSelected)
        XCTAssertFalse(app.buttons["series-detail-favorite"].exists, "The heart must not open the card")
        capture("favorites-series-cards")
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let detailFavorite = app.buttons["series-detail-favorite"]
        XCTAssertTrue(detailFavorite.waitForExistence(timeout: 5))
        XCTAssertTrue(detailFavorite.isSelected)
        capture("favorites-series-header-before-toggle")
        detailFavorite.tap()
        capture("favorites-series-header-after-toggle")
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == false"), object: detailFavorite)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 3), .completed)
        detailFavorite.tap(); XCTAssertTrue(detailFavorite.isSelected)
        capture("favorites-series-header")
        let episode = app.buttons["series-episode-play-http://127.0.0.1:8774/series/artwork/fixture/201.mp4"]
        for _ in 0..<5 { if episode.isHittable { break }; app.swipeUp() }
        episode.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        verifyMediaOptions(app)
        let episodeFavorite = app.buttons["player-favorite"]
        XCTAssertFalse(episodeFavorite.isSelected, "A saved series must not select its unsaved episode")
        XCTAssertEqual(episodeFavorite.value as? String, "Favorilerde değil")
        capture("favorite-episode-unsaved-player")
        episodeFavorite.tap()
        XCTAssertTrue(episodeFavorite.isSelected)
        assertNoFavoriteMenu(app)
        XCTAssertEqual(episodeFavorite.value as? String, "Bölüm favorilerde")
        episodeFavorite.tap()
        XCTAssertFalse(episodeFavorite.isSelected, "Removing the episode must not inherit its saved series state")
        episodeFavorite.tap(); XCTAssertTrue(episodeFavorite.isSelected)
        capture("favorites-episode-player")

        app.terminate()
        app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch(); openLibrary(app)
        openFavorites(app)
        let series = app.buttons["favorite-open-Kıyı Hikâyeleri"]
        let savedEpisode = app.buttons["favorite-open-Kıyı Hikâyeleri S01-E01"]
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        XCTAssertTrue(savedEpisode.exists)
        capture("favorites-series-and-episode")
        series.tap()
        XCTAssertTrue(app.buttons["series-season-2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["series-detail-favorite"].isSelected)
        XCTAssertFalse(app.otherElements["player-video"].exists, "A series favorite must open its seasons, not start its first episode")
    }

    func testContinueWatchingFavoritesMixEpisodesAndMovies() { verifyContinuationFavorites(large: false) }
    func testContinueWatchingFavoritesWithLargeText() { verifyContinuationFavorites(large: true) }

    func testEpisodeFavoriteStaysSelectedAcrossContinuationPlayerAndRelaunch() {
        let app = launchHistory()
        defer { app.terminate() }
        let heart = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-favorite-")).firstMatch
        for _ in 0..<5 { if heart.isHittable { break }; app.swipeUp() }
        XCTAssertFalse(heart.isSelected)
        heart.tap()
        XCTAssertTrue(heart.isSelected)
        assertNoFavoriteMenu(app)
        XCTAssertEqual(heart.value as? String, "Bölüm favorilerde")
        capture("favorite-scope-episode-continuation")

        app.terminate()
        app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch(); openLibrary(app)
        for _ in 0..<5 { if heart.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(heart.isSelected)
        XCTAssertEqual(heart.value as? String, "Bölüm favorilerde")
        openFavorites(app)
        let episode = app.buttons["favorite-open-Kıyı Hikâyeleri S01-E02"]
        XCTAssertTrue(episode.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["favorite-open-Kıyı Hikâyeleri"].exists)
        capture("favorite-scope-episode-badge")
        episode.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        let playerHeart = app.buttons["player-favorite"]
        XCTAssertTrue(playerHeart.isSelected)
        XCTAssertEqual(playerHeart.value as? String, "Bölüm favorilerde")
        playerHeart.tap()
        XCTAssertFalse(playerHeart.isSelected, "One tap must remove the saved episode")
        assertNoFavoriteMenu(app)
        XCTAssertEqual(playerHeart.value as? String, "Favorilerde değil")

        app.terminate(); app.launch(); openLibrary(app)
        for _ in 0..<5 { if heart.isHittable { break }; app.swipeUp() }
        XCTAssertFalse(heart.isSelected)
        XCTAssertEqual(heart.value as? String, "Favorilerde değil")
        capture("favorite-episode-unsaved-after-relaunch")
        openFavorites(app)
        XCTAssertFalse(app.buttons["favorite-open-Kıyı Hikâyeleri"].exists)
        XCTAssertFalse(app.buttons["favorite-open-Kıyı Hikâyeleri S01-E02"].exists)
    }

    func testMediaOptionsRemainVisibleWithoutSubtitleTracks() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FİLM: Macera")).firstMatch.tap()
        app.buttons["Mavi Yolculuk"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-media-options"].tap()
        XCTAssertTrue(app.staticTexts["subtitle-tracks-empty"].waitForExistence(timeout: 5))
        capture("media-options-without-subtitles")
    }

    private func verifyContinuationFavorites(large: Bool) {
        let app = launchHistory(large: large)
        defer { app.terminate() }
        let favorites = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-favorite-"))
        let carousel = app.scrollViews["continue-watching-carousel"]
        let first = favorites.element(boundBy: 0)
        for _ in 0..<5 { if first.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(first.isSelected, "Continue Watching must directly save the resumable episode")
        XCTAssertEqual(first.value as? String, "Bölüm favorilerde")
        assertNoFavoriteMenu(app)
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("favorites-continue-card-\(large)")
        let second = favorites.element(boundBy: 1)
        // A fast fling can skip the middle card. Drag and settle inside this
        // horizontal scroll view before checking the next heart.
        // Keep the gesture near the top: at accessibility sizes the lower
        // part of the card can sit behind the floating playback bar.
        let origin = carousel.coordinate(withNormalizedOffset: .zero)
        let y = min(80, carousel.frame.height / 2)
        let start = origin.withOffset(CGVector(dx: carousel.frame.width * 0.9, dy: y))
        let end = origin.withOffset(CGVector(dx: carousel.frame.width * 0.1, dy: y))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(second.isHittable)
        second.tap(); XCTAssertTrue(second.isSelected)
        openFavorites(app)
        let savedEpisode = app.buttons["favorite-open-Kıyı Hikâyeleri S01-E02"]
        XCTAssertTrue(savedEpisode.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["favorite-open-Kıyı Hikâyeleri"].exists)
        XCTAssertTrue(app.buttons["favorite-open-Mavi Yolculuk"].exists)
        capture("favorites-mixed-posters-\(large)")
        if !large {
            savedEpisode.tap()
            XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
            pause(app)
            let playerHeart = app.buttons["player-favorite"]
            XCTAssertTrue(playerHeart.isSelected)
            playerHeart.tap(); XCTAssertFalse(playerHeart.isSelected)
            assertNoFavoriteMenu(app)
            app.terminate()
            app.launchArguments.append("-mirivo-ui-preserve-library")
            app.launch(); openLibrary(app); openFavorites(app)
            XCTAssertTrue(app.buttons["favorite-open-Mavi Yolculuk"].waitForExistence(timeout: 10))
            XCTAssertFalse(savedEpisode.exists)
            XCTAssertFalse(app.buttons["favorite-open-Kıyı Hikâyeleri"].exists)
            capture("favorites-movie-after-episode-removal")
        }
    }

    private func assertNoFavoriteMenu(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for title in ["Diziyi favorilere ekle", "Diziyi favorilerden çıkar", "Bölümü favorilere ekle", "Bölümü favorilerden çıkar"] {
            XCTAssertFalse(app.buttons[title].exists, "Favorite controls must toggle directly without a scope menu", file: file, line: line)
        }
    }

    private func openFavorites(_ app: XCUIApplication) {
        let favorites = app.buttons["open-favorites"]
        for _ in 0..<6 { if favorites.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(favorites.waitForExistence(timeout: 5)); favorites.tap()
        XCTAssertTrue(app.scrollViews["favorites-grid"].waitForExistence(timeout: 5))
    }

    private func verifyMediaOptions(_ app: XCUIApplication) {
        let options = app.buttons["player-media-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5)); options.tap()
        XCTAssertTrue(app.buttons["close-media-options"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ses dili"].exists)
        XCTAssertTrue(app.staticTexts["Altyazı"].exists)
        capture("restored-audio-subtitle-options")
        app.buttons["close-media-options"].tap()
    }

    func testLiveChannelPickerFiltersAndSwitchesWithoutCategoryPages() {
        verifyLiveChannelPicker(large: false)
    }

    func testLiveChannelPickerWithLargeText() {
        verifyLiveChannelPicker(large: true)
    }

    private func verifyLiveChannelPicker(large: Bool) {
        let app = openCatalog(large: large, liveChannels: 4)
        defer { app.terminate() }
        let search = app.searchFields["channel-search-field"]
        search.tap(); search.typeText("Nova")
        let nova = app.buttons["Nova TV"].firstMatch
        XCTAssertTrue(nova.waitForExistence(timeout: 5)); nova.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-channel-picker"].tap()
        let current = app.buttons["live-channel-http://127.0.0.1:8774/live/artwork/fixture/1.mp4"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.isSelected)
        XCTAssertTrue(current.isHittable)
        XCTAssertFalse(app.buttons["browse-all-channels"].exists)
        XCTAssertEqual(app.staticTexts["live-channel-count"].label, "4 içerik", "The live switcher must exclude movies and episodes")
        XCTAssertLessThan(search.frame.maxY, current.frame.minY)
        let otherFavorite = app.buttons["live-channel-favorite-http://127.0.0.1:8774/live/artwork/fixture/2.mp4"]
        for _ in 0..<3 { if otherFavorite.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(otherFavorite.waitForExistence(timeout: 5))
        otherFavorite.tap(); XCTAssertTrue(otherFavorite.isSelected)
        XCTAssertTrue(current.isSelected, "Favoriting another station must not change the playing channel")
        XCTAssertTrue(app.buttons["close-playback-queue"].exists)
        capture("live-channel-picker-\(large)")

        app.buttons["live-channel-category"].tap()
        app.buttons["TR: Spor"].tap()
        let filteredCount = app.staticTexts["live-channel-count"]
        let filtered = NSPredicate(format: "label == %@", "2 içerik")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: filtered, object: filteredCount)], timeout: 5), .completed)
        XCTAssertFalse(current.exists)
        search.tap(); search.typeText("olmayan")
        XCTAssertTrue(app.descendants(matching: .any)["channel-search-empty"].firstMatch.waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "Plus")
        let next = app.buttons["live-channel-http://127.0.0.1:8774/live/artwork/fixture/4.mp4"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        app.buttons["dismiss-channel-search-keyboard"].tap()
        XCTAssertEqual(search.value as? String, "Plus")
        XCTAssertTrue(next.isHittable)
        capture("live-channel-picker-filtered-\(large)")
        next.tap()
        XCTAssertTrue(app.navigationBars["Spor Plus"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["close-playback-queue"].exists)
        pause(app)
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isSelected)
        XCTAssertTrue(next.isHittable)
        app.buttons["close-playback-queue"].tap()
        XCTAssertTrue(app.navigationBars["Spor Plus"].waitForExistence(timeout: 5))
    }

    func testLiveChannelPickerFindsCurrentChannelInLargePlaylist() {
        let app = openCatalog(liveChannels: 15348)
        defer { app.terminate() }
        let search = app.searchFields["channel-search-field"]
        search.tap(); search.typeText("Kanal 15000")
        let channel = app.buttons["Kanal 15000"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 10)); channel.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-channel-picker"].tap()
        let current = app.buttons["live-channel-http://127.0.0.1:8774/live/artwork/fixture/15000.mp4"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        let visible = NSPredicate { _, _ in current.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 10), .completed)
        XCTAssertTrue(current.isSelected)
        XCTAssertEqual(app.staticTexts["live-channel-count"].label, "15348 içerik")
        capture("live-channel-picker-large-playlist")
        search.tap(); search.typeText("Kanal 00005")
        let next = app.buttons["live-channel-http://127.0.0.1:8774/live/artwork/fixture/5.mp4"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(current.exists)
        app.buttons["dismiss-channel-search-keyboard"].tap()
        next.tap()
        XCTAssertTrue(app.navigationBars["Kanal 00005"].waitForExistence(timeout: 10))
    }

    func testCarPlayEpisodeControlsAndPictureSizing() { verifyExternalEpisodeControls(route: "carplay") }
    func testTVEpisodeControlsAndPictureSizing() { verifyExternalEpisodeControls(route: "tv") }

    private func verifyExternalEpisodeControls(route: String) {
        let app = openCatalog(ordinaryPlaylist: true, externalRoute: route)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        app.buttons["series-play"].tap()
        let video = app.otherElements["player-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        pause(app)
        XCTAssertFalse(app.buttons["player-large-controls"].exists)
        XCTAssertFalse(app.buttons["previous-episode"].isEnabled)
        XCTAssertTrue(app.buttons["next-episode"].isEnabled)
        XCTAssertTrue(app.buttons["player-play-on-phone"].exists)
        XCTAssertTrue(app.buttons["player-favorite"].exists)
        verifyMediaOptions(app)
        capture("\(route)-episode-controls")
        app.buttons["next-episode"].tap()
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S01-E02"].waitForExistence(timeout: 10))
        pause(app)
        XCTAssertTrue(app.buttons["previous-episode"].isEnabled)
        app.buttons["previous-episode"].tap()
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S01-E01"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-display-mode"].tap()
        XCTAssertTrue(app.buttons["Sığdır"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Uzat"].exists)
        capture("\(route)-picture-size-options")
        app.buttons["Uzat"].tap()
        app.buttons["player-display-mode"].tap()
        XCTAssertTrue(app.buttons["Sığdır"].waitForExistence(timeout: 5))
        app.buttons["Sığdır"].tap()
        app.buttons["tv-connection"].tap()
        let connected = app.descendants(matching: .any)["connection-airplay"].firstMatch.waitForExistence(timeout: 5)
        capture("\(route)-working-connection-button")
        XCTAssertTrue(connected)
        app.buttons["Kapat"].tap()
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(app.buttons["Kıyı Hikâyeleri S01-E02"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        capture("\(route)-episode-list-without-search")
    }

    func testSeriesPosterOpensFullScreenZoomsAndReturnsToDetails() {
        let app = openCatalog(ordinaryPlaylist: true)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let poster = app.buttons["media-artwork-preview-open"]
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        let originalFrame = poster.frame
        poster.tap()
        let image = app.images["media-artwork-preview-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        let close = app.buttons["media-artwork-preview-close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("series-poster-fullscreen")
        let fittedHeight = image.frame.height
        image.doubleTap()
        let zoomed = NSPredicate { _, _ in image.frame.height > fittedHeight + 40 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: zoomed, object: app)], timeout: 5), .completed)
        capture("series-poster-zoomed")
        image.doubleTap()
        close.tap()
        XCTAssertTrue(poster.waitForExistence(timeout: 5))
        XCTAssertTrue(poster.isHittable)
        XCTAssertEqual(poster.frame.minY, originalFrame.minY, accuracy: 2)
        XCTAssertTrue(app.buttons["series-play"].exists)
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("series-poster-dismissed")
    }

    func testContentDetailsOpenWithoutMovingSeriesLayout() {
        verifyDetailsPresentation(large: false)
    }

    func testContentDetailsPresentationWithLargeText() {
        verifyDetailsPresentation(large: true)
    }

    private func verifyDetailsPresentation(large: Bool) {
        let app = openCatalog(large: large, ordinaryPlaylist: true)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        let toggle = app.buttons["media-details-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2024"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        XCTAssertFalse(app.staticTexts["media-synopsis"].exists)
        let title = app.staticTexts["Kıyı Hikâyeleri"].firstMatch
        XCTAssertTrue(title.exists)
        for _ in 0..<8 { if title.isHittable { break }; app.swipeUp() }
        title.tap()
        XCTAssertFalse(app.staticTexts["media-synopsis"].exists)
        for _ in 0..<8 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        capture("series-redesign-\(large)")
        let originalToggleFrame = toggle.frame
        for attempt in 0..<3 {
            toggle.tap()
            let summary = app.staticTexts["media-synopsis"]
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertTrue(summary.label.hasSuffix("birlikte ortaya çıkarırlar."))
            for _ in 0..<8 { if summary.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(summary.isHittable)
            if attempt == 0 { capture("series-information-\(large)") }
            let close = app.buttons["media-details-close"]
            XCTAssertTrue(close.isHittable); close.tap()
            XCTAssertTrue(summary.waitForNonExistence(timeout: 5))
            XCTAssertTrue(toggle.isHittable)
            XCTAssertEqual(toggle.frame.minY, originalToggleFrame.minY, accuracy: 1)
            XCTAssertEqual(toggle.frame.height, originalToggleFrame.height, accuracy: 1)
            XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        }
        capture("series-information-dismissed-\(large)")
    }

    func testSeriesHasNoSearchAndPlayActionFollowsSelectedSeason() {
        verifySeriesActions(large: false)
    }

    func testSeriesActionsWithLargeText() {
        verifySeriesActions(large: true)
    }

    func testSingleSeasonDetailsKeepEpisodesReachableWithMiniPlayer() {
        let app = openCatalog(singleSeason: true)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        XCTAssertTrue(app.buttons["series-play"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["series-season-1"].exists)
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        capture("series-single-season")
        app.buttons["media-details-toggle"].tap()
        XCTAssertTrue(app.staticTexts["media-synopsis"].waitForExistence(timeout: 10))
        capture("series-single-season-information")
        app.buttons["media-details-close"].tap()
        app.buttons["series-play"].tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let miniPlayer = app.buttons["now-playing-open"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        let episode = app.buttons["Kıyı Hikâyeleri S01-E10"].firstMatch
        for _ in 0..<8 {
            if episode.isHittable && episode.frame.maxY < miniPlayer.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(episode.isHittable)
        XCTAssertLessThan(episode.frame.maxY, miniPlayer.frame.minY)
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        capture("series-single-season-mini-player")
        episode.tap()
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S01-E10"].waitForExistence(timeout: 10))
    }

    private func verifySeriesActions(large: Bool) {
        let app = openCatalog(large: large)
        defer { app.terminate() }
        openSeriesCategory(app)
        app.buttons["series-open-Kıyı Hikâyeleri"].tap()
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        capture("series-detail-hero-\(large)")
        let season = app.buttons["series-season-2"]
        for _ in 0..<10 { if season.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(season.isHittable); season.tap()
        XCTAssertTrue(season.isSelected)
        // The poster also carries the first episode's title. Match the actual
        // episode control when checking that the previous season disappeared.
        XCTAssertFalse(app.buttons["series-episode-play-http://127.0.0.1:8774/series/artwork/fixture/201.mp4"].exists)
        let play = app.buttons["series-play"]
        for _ in 0..<10 { if play.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(play.label.contains("2. sezon"))
        play.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Kıyı Hikâyeleri S02-E01"].exists)
        pause(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["now-playing-open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
        for _ in 0..<10 { if season.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(season.isSelected)
        capture("series-selected-season-\(large)")
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

    func testMovieSortingAndPlaybackMenuStayWithinCategory() {
        let app = openCatalog()
        defer { app.terminate() }
        let sort = app.buttons["library-sort"]
        XCTAssertFalse(sort.exists)
        capture("sort-categories")
        let category = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FİLM: Sinema")).firstMatch
        for _ in 0..<4 { if category.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(category.isHittable); category.tap()
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertEqual(sort.value as? String, "Son eklenenler")
        sort.tap(); app.buttons["Ada göre (Z–A)"].tap()
        let lastAlphabetically = app.buttons["Yolun Ötesi"].firstMatch
        let firstAlphabetically = app.buttons["Mavi Yolculuk"].firstMatch
        XCTAssertTrue(lastAlphabetically.waitForExistence(timeout: 5))
        sort.tap(); app.buttons["Son eklenenler"].tap()
        let newest = app.buttons["Son Işık"].firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let sorted = NSPredicate { _, _ in newest.frame.minY < firstAlphabetically.frame.minY }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: sorted, object: app)], timeout: 10), .completed)
        capture("sort-movies-recently-added")
        firstAlphabetically.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        pause(app)
        app.buttons["player-channel-picker"].tap()
        XCTAssertTrue(firstAlphabetically.waitForExistence(timeout: 5))
        XCTAssertTrue(lastAlphabetically.exists)
        XCTAssertFalse(app.buttons["browse-all-channels"].exists)
        XCTAssertFalse(app.buttons["series-open-Kıyı Hikâyeleri"].exists)
        XCTAssertFalse(app.buttons["Nova TV"].exists)
        capture("movie-playback-category")
    }

    func testSeriesSeasonsSortAndKeepPlaybackQueueWithinSeries() {
        let app = openCatalog()
        defer { app.terminate() }
        openSeriesCategory(app)
        XCTAssertFalse(app.buttons["library-sort"].exists)
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
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-playback-access", "-mirivo-ui-artwork-history", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
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
        if !button.waitForExistence(timeout: 2) {
            // Controls can auto-hide while a busy simulator finishes navigation.
            app.otherElements["player-video"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
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
        app.buttons["media-details-close"].tap()
        for _ in 0..<8 { if episode.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields["channel-search-field"].exists)
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
        capture("metadata-error-presented")
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
        // Movie fixtures are intentionally short. Keep the player alive while
        // the information sheet and metadata error states are inspected.
        if app.buttons["player-play-pause"].exists { pause(app) }
        let toggle = app.buttons["media-details-toggle"]
        for _ in 0..<8 { if toggle.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.buttons["media-details-close"].waitForExistence(timeout: 5))
    }

    private func openCatalog(large: Bool = false, ordinaryPlaylist: Bool = false, movieEpisodes: Bool = false, externalRoute: String? = nil, singleSeason: Bool = false, liveChannels: Int? = nil, favoriteLists: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-playback-access", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        if externalRoute == "carplay" { app.launchArguments += ["-mirivo-ui-carplay", "-mirivo-ui-carplay-display"] }
        else if externalRoute == "tv" { app.launchArguments.append("-mirivo-ui-external-display") }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        openLibrary(app)
        let add = app.buttons["add-source"]
        for _ in 0..<4 { if add.isHittable { break }; app.swipeUp() }
        for _ in 0..<2 {
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.textFields["source-name"].waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(app.textFields["source-name"].exists)
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Görsel Kitaplık")
        app.textFields["source-url"].tap()
        let url = favoriteLists ? "http://127.0.0.1:8774/favorite-lists.m3u" : liveChannels.map { "http://127.0.0.1:8774/live-picker.m3u?count=\($0)" } ?? (singleSeason ? "http://127.0.0.1:8774/catalog-single-season.m3u" : movieEpisodes ? "http://127.0.0.1:8774/catalog-movie-episodes.m3u" : ordinaryPlaylist ? "http://127.0.0.1:8774/catalog.m3u" : "http://127.0.0.1:8774/catalog/get.php?username=artwork&password=fixture&type=m3u_plus")
        app.textFields["source-url"].typeText(url)
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
