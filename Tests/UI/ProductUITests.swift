import XCTest

final class ProductUITests: XCTestCase {
    func testPhysicalNativePiPReturnInline() throws { try physicalPiPReturn(kind: "mp4", fullscreen: false) }
    func testPhysicalNativePiPReturnFullscreen() throws { try physicalPiPReturn(kind: "mp4", fullscreen: true) }
    func testPhysicalCompatibilityPiPReturnInline() throws { try physicalPiPReturn(kind: "mkv", fullscreen: false) }
    func testPhysicalCompatibilityPiPReturnFullscreen() throws { try physicalPiPReturn(kind: "mkv", fullscreen: true) }
    func testPhysicalLivePiPReturnInline() throws { try physicalPiPReturn(kind: "hls", fullscreen: false) }
    func testPhysicalLivePiPReturnFullscreen() throws { try physicalPiPReturn(kind: "hls", fullscreen: true) }
    func testPhysicalLastWatchedPiPReturnInline() throws { try physicalPiPReturn(kind: "last-watched", fullscreen: false) }
    func testPhysicalLastWatchedPiPReturnFullscreen() throws { try physicalPiPReturn(kind: "last-watched", fullscreen: true) }

    private func physicalPiPReturn(kind: String, fullscreen: Bool) throws {
        guard ProcessInfo.processInfo.environment["MIRIVO_PHYSICAL_PIP_QA"] == "1" else {
            throw XCTSkip("Opt-in physical iPhone test; copy the local PiP fixture into the app cache first")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR", "-mirivo-pip-trace"]
        if kind != "last-watched" { app.launchArguments += ["-mirivo-pip-probe", kind] }
        if kind == "hls" {
            guard let url = ProcessInfo.processInfo.environment["MIRIVO_PIP_QA_LIVE_URL"] else {
                throw XCTSkip("Supply the local live HLS fixture URL to run this case")
            }
            app.launchEnvironment["MIRIVO_PIP_QA_LIVE_URL"] = url
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        if kind == "last-watched" {
            let resume = app.buttons["last-watched-open"]
            XCTAssertTrue(resume.waitForExistence(timeout: 10))
            resume.tap()
        }
        let video = app.otherElements["player-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 15))
        // Never tap the center to reveal chrome: that is also Play/Pause.
        let ready = NSPredicate { _, _ in
            app.buttons["player-pip"].exists && app.buttons["player-pip"].isEnabled &&
                app.buttons["player-play-pause"].exists && app.buttons["player-play-pause"].label == "Duraklat"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 30), .completed)
        if !app.buttons["player-fullscreen"].isHittable {
            video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        }
        if fullscreen { app.buttons["player-fullscreen"].tap() }
        let expected = video.frame
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for route in ["app", "pip"] {
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 2)
            let pipWindow = springboard.windows["PIP-SBInteractionPassThroughView"]
            XCTAssertTrue(pipWindow.waitForExistence(timeout: 5), "System PiP must be active")
            capture("physical-pip-\(kind)-\(fullscreen ? "fullscreen" : "inline")-\(route)", app: springboard)
            if route == "pip" {
                // iOS hides its controls while XCTest resolves individual
                // snapshots. Reveal them within the observed PiP window first.
                pipWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
                pipWindow.buttons["Tam ekrana dön"].tap()
            } else { app.activate() }
            XCTAssertTrue(video.waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 3)
            XCTAssertEqual(video.frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(video.frame.height, expected.height, accuracy: 1)
            capture("physical-return-\(kind)-\(fullscreen ? "fullscreen" : "inline")-\(route)", app: app)
        }
    }

    func testContinueWatchingIsCompactSearchableRemovableAndResumesAfterRelaunch() {
        let app = launch(continuations: true)
        defer { app.terminate() }
        app.buttons["page-library"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-open-"))
        XCTAssertTrue(app.buttons["continue-watching-all"].waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 3, "Only three recent items belong on the sources screen")
        XCTAssertFalse(app.buttons["last-watched-open"].exists, "The sources page must not duplicate a saved continuation in the bottom bar")
        capture("continue-watching-compact", app: app)
        app.buttons["continue-watching-all"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-list-open-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 5)
        capture("continue-watching-all", app: app)
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("Uzun Yol")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.swipeLeft()
        app.buttons["Listeden kaldır"].tap()
        XCTAssertTrue(app.staticTexts["İçerik bulunamadı"].waitForExistence(timeout: 5))
        search.typeText("\n")
        // On iOS 26 an active bottom search field replaces the sheet toolbar.
        if !app.buttons["close-continue-watching"].exists, app.buttons["kapat"].exists {
            app.buttons["kapat"].tap()
        }
        app.buttons["close-continue-watching"].tap()
        app.terminate()
        app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch(); app.buttons["page-library"].tap()
        XCTAssertTrue(app.buttons["continue-watching-all"].waitForExistence(timeout: 10))
        app.buttons["continue-watching-all"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 4)
        rows.firstMatch.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let resumed = NSPredicate { _, _ in
            let value = app.sliders["Oynatma konumu"].value as? String ?? ""
            let parts = value.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 42
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: app)], timeout: 10), .completed)
        capture("continue-watching-resumed", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["now-playing-open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Şimdi oynatılıyor")).count, 1, "Active playback belongs in the bottom bar only")
        capture("continue-watching-with-active-player", app: app)
    }

    func testPlaybackQueueSearchSelectsAnotherChannel() {
        let app = launch(continuations: true)
        defer { app.terminate() }
        app.buttons["page-library"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Mirivo Demo", "Oynatma listesi")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        reveal(source, in: app)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tüm kanallar")).firstMatch
        if !all.waitForExistence(timeout: 3), source.isHittable {
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        XCTAssertTrue(all.waitForExistence(timeout: 10)); all.tap()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let pause = app.buttons["player-play-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        if pause.label == "Duraklat" { pause.tap() }
        let queue = app.buttons["player-channel-picker"]
        let ready = NSPredicate { _, _ in queue.exists && queue.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: queue)], timeout: 10), .completed)
        queue.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("02")
        let channel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 02")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 5))
        capture("audit-player-queue-search", app: app)
        channel.tap()
        XCTAssertTrue(app.navigationBars["Mirivo Demo 02"].waitForExistence(timeout: 5))
        capture("audit-player-queue-selected", app: app)
    }

    func testPlayerTVPickerAndManualFullscreenExitPersist() {
        let app = launch(continuations: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["page-library"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-open-")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let video = app.otherElements["player-video"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 5), .completed)
        if app.buttons["Tamam"].waitForExistence(timeout: 2) { app.buttons["Tamam"].tap() }
        if !app.buttons["tv-connection"].isHittable { video.tap() }
        app.buttons["tv-connection"].tap()
        XCTAssertTrue(app.buttons["Kapat"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 12)
        XCTAssertTrue(app.buttons["Kapat"].isHittable, "TV search must survive both chrome and discovery timers")
        capture("tv-picker-stays-open", app: app)
        app.buttons["Kapat"].tap()
        if !app.buttons["player-fullscreen"].isHittable { video.tap() }
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.28))
            .press(forDuration: 0.05, thenDragTo: video.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.78)))
        let portrait = NSPredicate { _, _ in app.frame.height > app.frame.width }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: app)], timeout: 5), .completed)
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 2)
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
        XCTAssertLessThan(video.frame.height, video.frame.width)
        capture("manual-fullscreen-exit-persists", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 5), .completed)
        if !app.buttons["player-options"].isHittable { video.tap() }
        app.buttons["player-options"].tap()
        app.buttons["Durdur"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: app)], timeout: 5), .completed)
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            XCTAssertGreaterThan(app.frame.height, app.frame.width, "Stopped player must not re-enable landscape")
        }
        capture("continue-watching-stop-stays-portrait", app: app)
    }

    func testContinueWatchingLargeTextLayout() {
        let app = launch(large: true, continuations: true)
        defer { app.terminate() }
        app.buttons["page-library"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "continue-watching-open-")).firstMatch
        reveal(card, in: app)
        XCTAssertTrue(card.isHittable)
        if card.frame.maxY > app.frame.maxY - 80 { app.swipeUp() }
        capture("continue-watching-large-text", app: app)
    }
    func testSourceRefreshCompletesWhenProviderReturnsImmediately() {
        let app = launch()
        defer { app.terminate() }
        guard openSourceEditor(in: app) else { return }
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Refresh QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.m3u")
        app.buttons["Ekle"].tap()
        let menu = app.buttons.matching(NSPredicate(format: "label == %@", "Refresh QA")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let refresh = app.buttons["Bilgileri yenile"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        refresh.tap()
        let progress = app.otherElements["source-refresh-progress"]
        // XCTest waits for UI idleness after tap, beyond this brief HUD's
        // display interval. Capture it externally during the tap; verify the
        // finished state here without lengthening the shipping spinner.
        let finished = NSPredicate { _, _ in !progress.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: progress)], timeout: 5), .completed)
        XCTAssertTrue(menu.exists)
    }

    func testAudioSubtitlesAndLastWatchedSurviveApplicationRelaunch() {
        let app = launch()
        defer { app.terminate() }
        guard openSourceEditor(in: app) else { return }
        app.buttons["source-kind"].tap(); app.buttons["Yayın bağlantısı"].tap()
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Tracks QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/tracks/options.mp4")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Tracks QA", "Yayın bağlantısı")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let channel = app.buttons["Tracks QA"].firstMatch
        if !channel.waitForExistence(timeout: 3), source.isHittable {
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        XCTAssertTrue(channel.waitForExistence(timeout: 10)); channel.tap()
        let options = app.buttons["player-media-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        app.buttons["player-play-pause"].tap()
        options.tap()
        let audio = app.buttons["audio-track-audio-1"]
        let subtitle = app.buttons["subtitle-track-subtitle-0"]
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap(); XCTAssertTrue(audio.isSelected)
        XCTAssertTrue(subtitle.exists); subtitle.tap(); XCTAssertTrue(subtitle.isSelected)
        capture("player-audio-and-subtitles", app: app)
        app.buttons["close-media-options"].tap()
        app.buttons["player-fullscreen"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5)); options.tap()
        app.buttons["subtitles-off"].tap()
        XCTAssertTrue(app.buttons["subtitles-off"].isSelected)
        capture("player-fullscreen-subtitles-off", app: app)
        app.buttons["close-media-options"].tap()
        if !app.buttons["player-fullscreen"].isHittable {
            app.otherElements["player-video"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        }
        app.buttons["player-fullscreen"].tap()
        app.otherElements["player-video"].coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.32)).doubleTap()
        let position = app.sliders["Oynatma konumu"].value as? String
        XCTAssertNotEqual(position, "00:00")
        // Let the pause/seek checkpoint reach persistent storage before a cold launch.
        Thread.sleep(forTimeInterval: 5.2)
        app.terminate()
        app.launchArguments.append("-mirivo-ui-preserve-library")
        app.launch()
        let resume = app.buttons["last-watched-open"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["now-playing-open"].exists, "Cold launch must not claim playback or start it automatically")
        XCTAssertFalse(app.otherElements["player-video"].exists)
        capture("last-watched-after-relaunch", app: app)
        resume.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        let resumed = NSPredicate { _, _ in
            let value = app.sliders["Oynatma konumu"].value as? String ?? ""
            return !value.isEmpty && value != "00:00"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: app)], timeout: 10), .completed)
        capture("last-watched-resumed", app: app)
    }

    // These captures use the shipping views and an original local test video.
    // The playlist is served by scripts/capture_store_screenshots.py, never bundled.
    func testAppStoreScreenshots() {
        captureStoreLanguage("tr")
        captureStoreLanguage("en")
    }
    func testAppStoreScreenshots_zh_Hans() { captureStoreLanguage("zh-Hans") }
    func testAppStoreScreenshots_zh_Hant() { captureStoreLanguage("zh-Hant") }
    func testAppStoreScreenshots_ja() { captureStoreLanguage("ja") }
    func testAppStoreScreenshots_ko() { captureStoreLanguage("ko") }
    func testAppStoreScreenshots_fr() { captureStoreLanguage("fr") }
    func testAppStoreScreenshots_de() { captureStoreLanguage("de") }
    func testAppStoreScreenshots_es() { captureStoreLanguage("es") }
    func testAppStoreScreenshots_it() { captureStoreLanguage("it") }
    func testAppStoreScreenshots_pt_BR() { captureStoreLanguage("pt-BR") }
    func testAppStoreScreenshots_ru() { captureStoreLanguage("ru") }
    func testAppStoreScreenshots_nl() { captureStoreLanguage("nl") }
    func testAppStoreScreenshots_pl() { captureStoreLanguage("pl") }
    func testAppStoreScreenshots_sv() { captureStoreLanguage("sv") }
    func testAppStoreScreenshots_uk() { captureStoreLanguage("uk") }
    func testAppStoreScreenshots_ar() { captureStoreLanguage("ar") }
    func testAppStoreScreenshots_he() { captureStoreLanguage("he") }
    func testAppStoreScreenshots_th() { captureStoreLanguage("th") }
    func testAppStoreScreenshots_vi() { captureStoreLanguage("vi") }
    func testAppStoreScreenshots_id() { captureStoreLanguage("id") }
    func testAppStoreScreenshots_hi() { captureStoreLanguage("hi") }

    func testAppStorePlayer_tr() { captureStoreLanguage("tr", playerOnly: true) }
    func testAppStorePlayer_en() { captureStoreLanguage("en", playerOnly: true) }
    func testAppStorePlayer_ar() { captureStoreLanguage("ar", playerOnly: true) }
    func testAppStorePlayer_he() { captureStoreLanguage("he", playerOnly: true) }
    func testAppStorePlayer_hi() { captureStoreLanguage("hi", playerOnly: true) }
    func testAppStorePlayer_id() { captureStoreLanguage("id", playerOnly: true) }
    func testAppStorePlayer_th() { captureStoreLanguage("th", playerOnly: true) }
    func testAppStorePlayer_vi() { captureStoreLanguage("vi", playerOnly: true) }
    func testAppStorePlayer_de() { captureStoreLanguage("de", playerOnly: true) }
    func testAppStorePlayer_fr() { captureStoreLanguage("fr", playerOnly: true) }
    func testAppStorePlayer_es() { captureStoreLanguage("es", playerOnly: true) }
    func testAppStorePlayer_it() { captureStoreLanguage("it", playerOnly: true) }
    func testAppStorePlayer_pt_BR() { captureStoreLanguage("pt-BR", playerOnly: true) }
    func testAppStorePlayer_nl() { captureStoreLanguage("nl", playerOnly: true) }
    func testAppStorePlayer_pl() { captureStoreLanguage("pl", playerOnly: true) }
    func testAppStorePlayer_sv() { captureStoreLanguage("sv", playerOnly: true) }
    func testAppStorePlayer_ru() { captureStoreLanguage("ru", playerOnly: true) }
    func testAppStorePlayer_uk() { captureStoreLanguage("uk", playerOnly: true) }
    func testAppStorePlayer_ja() { captureStoreLanguage("ja", playerOnly: true) }
    func testAppStorePlayer_ko() { captureStoreLanguage("ko", playerOnly: true) }
    func testAppStorePlayer_zh_Hans() { captureStoreLanguage("zh-Hans", playerOnly: true) }
    func testAppStorePlayer_zh_Hant() { captureStoreLanguage("zh-Hant", playerOnly: true) }

    // Labels are copied from the current shipping catalogs for locale-specific UI actions.
    private let screenshotLabels: [String: [String]] = [
        "tr": ["Ekle", "Oynatma listesi", "Tüm kanallar", "Duraklat", "Xtream Codes"],
        "en": ["Add", "Playlist", "All channels", "Pause", "Xtream Codes"],
        "zh-Hans": ["添加", "播放列表", "所有频道", "暂停", "Xtream Codes"],
        "zh-Hant": ["加入", "播放列表", "所有頻道", "暫停", "Xtream Codes"],
        "ja": ["追加", "プレイリスト", "すべてのチャンネル", "一時停止", "Xtream Codes"],
        "ko": ["추가", "재생목록", "모든 채널", "일시 정지", "Xtream Codes"],
        "fr": ["Ajouter", "Liste de lecture", "Toutes les chaînes", "Pause", "Xtream Codes"],
        "de": ["Hinzufügen", "Wiedergabeliste", "Alle Kanäle", "Pause", "Xtream Codes"],
        "es": ["Añadir", "Lista de reproducción", "Todos los canales", "Pausar", "Xtream Codes"],
        "it": ["Aggiungi", "Playlist", "Tutti i canali", "Pausa", "Xtream Codes"],
        "pt-BR": ["Adicionar", "Lista de reprodução", "Todos os canais", "Pausar", "Xtream Codes"],
        "ru": ["Добавить", "Плейлист", "Все каналы", "Пауза", "Xtream Codes"],
        "nl": ["Toevoegen", "Afspeellijst", "Alle kanalen", "Pauzeren", "Xtream Codes"],
        "pl": ["Dodaj", "Playlista", "Wszystkie kanały", "Wstrzymaj", "Xtream Codes"],
        "sv": ["Lägg till", "Spellista", "Alla kanaler", "Pausa", "Xtream Codes"],
        "uk": ["Додати", "Плейліст", "Усі канали", "Пауза", "Xtream Codes"],
        "ar": ["إضافة", "قائمة تشغيل", "جميع القنوات", "إيقاف مؤقت", "Xtream Codes"],
        "he": ["הוספה", "רשימת השמעה", "כל הערוצים", "השהיה", "Xtream Codes"],
        "th": ["เพิ่ม", "เพลย์ลิสต์", "ทุกช่อง", "หยุดชั่วคราว", "Xtream Codes"],
        "vi": ["Thêm", "Danh sách phát", "Tất cả kênh", "Tạm dừng", "Xtream Codes"],
        "id": ["Tambah", "Daftar putar", "Semua saluran", "Jeda", "Xtream Codes"],
        "hi": ["जोड़ें", "प्लेलिस्ट", "सभी चैनल", "विराम दें", "Xtream Codes"],
    ]

    private func captureStoreLanguage(_ language: String, playerOnly: Bool = false) {
        let labels = screenshotLabels[language]!
        let app = launch(language: language)
        guard openSourceEditor(in: app) else { app.terminate(); return }
        // iPad's centered form sheet continues moving after it enters AX.
        Thread.sleep(forTimeInterval: 0.8)
        app.textFields["source-name"].tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            app.textFields["source-name"].tap()
        }
        app.textFields["source-name"].typeText("Mirivo Demo")
        app.textFields["source-url"].tap()
        app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.m3u")
        app.buttons[labels[0]].tap()
        XCTAssertTrue(app.staticTexts["Mirivo Demo"].waitForExistence(timeout: 10))
        if !playerOnly { capture("store-\(language)-01-iptv", app: app) }
        let demoSource = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Mirivo Demo", labels[1])).firstMatch
        demoSource.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let allChannels = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", labels[2])).firstMatch
        if !allChannels.waitForExistence(timeout: 3), demoSource.exists {
            demoSource.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        guard allChannels.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        allChannels.tap()
        let firstChannel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch
        if !firstChannel.waitForExistence(timeout: 3), allChannels.exists && allChannels.isHittable {
            allChannels.tap()
        }
        guard firstChannel.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        if !playerOnly { capture("store-\(language)-02-channels", app: app) }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch.tap()
        let pause = app.buttons[labels[3]].firstMatch
        if !pause.waitForExistence(timeout: 3) {
            let channel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch
            if channel.exists && channel.isHittable { channel.tap() }
        }
        guard pause.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        pause.tap()
        capture("store-\(language)-03-player", app: app)
        app.terminate()
        if playerOnly { return }

        let home = launch(language: language)
        XCTAssertTrue(home.buttons["share-photos"].waitForExistence(timeout: 10))
        reveal(home.buttons["share-photos"], in: home)
        capture("store-\(language)-04-sharing", app: home)
        reveal(home.buttons["connection-guide"], in: home)
        home.buttons["connection-guide"].tap()
        XCTAssertTrue(home.buttons["guide-AirPlay"].waitForExistence(timeout: 10))
        home.buttons["guide-AirPlay"].tap()
        capture("store-\(language)-06-airplay", app: home)
        home.terminate()

        let editor = launch(language: language)
        guard openSourceEditor(in: editor) else { editor.terminate(); return }
        Thread.sleep(forTimeInterval: 0.8)
        editor.buttons["source-kind"].tap()
        let xtream = editor.buttons[labels[4]].firstMatch
        XCTAssertTrue(xtream.waitForExistence(timeout: 5))
        xtream.tap()
        if !editor.textFields["source-username"].waitForExistence(timeout: 3) {
            if !xtream.exists { editor.buttons["source-kind"].tap() }
            XCTAssertTrue(xtream.waitForExistence(timeout: 5))
            xtream.tap()
        }
        guard editor.textFields["source-username"].waitForExistence(timeout: 10) else {
            XCTFail(editor.debugDescription)
            editor.terminate()
            return
        }
        capture("store-\(language)-05-xtream", app: editor)
        editor.terminate()
    }
    func testPlayerModesGesturesAndControlLayout() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        guard openSourceEditor(in: app) else { return }
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Player QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.m3u")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Player QA", "Oynatma listesi")).firstMatch
        guard source.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        Thread.sleep(forTimeInterval: 0.8)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tüm kanallar")).firstMatch
        if !all.waitForExistence(timeout: 3), source.isHittable {
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        guard all.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        all.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch.tap()
        let video = app.otherElements["player-video"]
        guard video.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
        let pause = app.buttons["player-play-pause"]
        if !pause.waitForExistence(timeout: 2) {
            video.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.32)).tap()
        }
        guard pause.waitForExistence(timeout: 3) else { XCTFail(app.debugDescription); return }
        XCTAssertEqual(pause.label, "Duraklat"); pause.tap()
        let vehicle = app.buttons["player-large-controls"]
        let fullscreen = app.buttons["player-fullscreen"]
        let pip = app.buttons["player-pip"]
        let playlist = app.buttons["player-channel-picker"]
        for button in [vehicle, fullscreen, pip, playlist] {
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(video.frame.contains(button.frame))
        }
        XCTAssertFalse(app.buttons["player-options"].exists)
        XCTAssertLessThanOrEqual(fullscreen.frame.maxY, pip.frame.minY)
        XCTAssertLessThanOrEqual(vehicle.frame.maxX, pip.frame.minX)
        XCTAssertLessThanOrEqual(pip.frame.maxX, playlist.frame.minX)
        // The right and left halves must seek while paused, without toggling play.
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.32)).doubleTap()
        capture("player-seek-forward-inline", app: app, waitForTransition: false)
        let timeline = app.sliders["Oynatma konumu"]
        let forwarded = NSPredicate { _, _ in
            let value = timeline.value as? String ?? ""
            return value.hasPrefix("00:1")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: forwarded, object: timeline)], timeout: 5), .completed)
        XCTAssertEqual(pause.label, "Oynat")
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.32)).doubleTap()
        capture("player-seek-backward-inline", app: app, waitForTransition: false)
        XCTAssertEqual(pause.label, "Oynat")
        capture("player-inline-custom-controls", app: app)
        vehicle.tap()
        XCTAssertTrue(vehicle.isSelected)
        XCTAssertFalse(app.buttons["pro-close"].exists, "Free viewing must include large controls")
        capture("player-free-large-controls", app: app)
        fullscreen.tap() // Switch from large controls to the standard fullscreen layout.
        XCTAssertEqual(fullscreen.label, "Tam ekrandan çık")
        fullscreen.tap()
        XCTAssertEqual(fullscreen.label, "Tam ekran")
        fullscreen.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 5), .completed)
        if app.staticTexts["Yatay tam ekran hareketleri"].waitForExistence(timeout: 3) {
            capture("audit-player-gesture-intro", app: app)
            app.buttons["Tamam"].tap()
        }
        let close = app.buttons["player-fullscreen"]
        video.pinch(withScale: 2, velocity: 1)
        pause.tap()
        app.buttons["player-options"].tap()
        XCTAssertTrue(app.buttons["Görüntüyü sığdır"].waitForExistence(timeout: 3))
        guard app.buttons["Görüntüyü sığdır"].exists else { XCTFail(app.debugDescription); return }
        capture("player-fullscreen-options", app: app)
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.buttons["Görüntüyü sığdır"].isHittable, "The popover must survive the old four-second timeout")
        app.buttons["Görüntüyü sığdır"].tap()
        pause.tap()
        // A paused fixture lets us verify the full menu timeout without ending
        // this short video. It must stay open near 30s and then dismiss itself.
        app.buttons["player-options"].tap()
        let stopOption = app.buttons["Durdur"]
        XCTAssertTrue(stopOption.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 27)
        XCTAssertTrue(stopOption.isHittable)
        let optionsClosed = NSPredicate { _, _ in !stopOption.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: optionsClosed, object: stopOption)], timeout: 6), .completed)
        Thread.sleep(forTimeInterval: 0.8) // Finish the UIKit dismissal before rotating.
        let options = app.buttons["player-options"]
        if !options.isHittable { video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap() }
        XCTAssertGreaterThanOrEqual(options.frame.minX, 40)
        XCTAssertLessThan(options.frame.maxX, app.frame.maxX - 40, "Keep controls inside the landscape safe area")
        capture("player-fullscreen-landscape-controls", app: app)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.32)).doubleTap()
        capture("player-seek-forward-landscape", app: app, waitForTransition: false)
        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { _, _ in
            app.frame.height > app.frame.width && video.frame.height > video.frame.width
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: app)], timeout: 5), .completed)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.28))
            .press(forDuration: 0.05, thenDragTo: video.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.72)))
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 5))
        XCTAssertEqual(close.label, "Tam ekran")
        XCTAssertLessThan(video.frame.height, video.frame.width)
        capture("player-inline-after-fullscreen", app: app)
    }

    func testProCloseButtonDismissesScreen() {
        let app = launch()
        defer { app.terminate() }
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let pro = app.buttons["settings-pro"]
        if !pro.waitForExistence(timeout: 3), settings.isHittable { settings.tap() }
        guard pro.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        Thread.sleep(forTimeInterval: 0.8)
        pro.tap()
        let close = app.buttons["pro-close"]
        if !close.waitForExistence(timeout: 3), pro.isHittable { pro.tap() }
        guard close.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons["Tamam"].tap() }
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
    }

    func testSourceLimitProSheetHasOneCloseButton() {
        let app = launch()
        defer { app.terminate() }
        guard openSourceEditor(in: app) else { return }
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Source Limit QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.m3u")
        app.buttons["Ekle"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Source Limit QA")).firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["add-source"].tap()
        let close = app.buttons["pro-close"]
        guard close.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons["Tamam"].tap() }
        let dismissButtons = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Kapat", "Bitti"))
        XCTAssertEqual(dismissButtons.count, 1)
        capture("source-limit-pro-single-close", app: app)
        close.tap()
        XCTAssertTrue(app.buttons["add-source"].waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
    }

    private func openSourceEditor(in app: XCUIApplication) -> Bool {
        let library = app.buttons["page-library"]
        library.tap()
        let selected = NSPredicate(format: "selected == true")
        if !selected.evaluate(with: library) { library.tap() }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: library)], timeout: 5) == .completed else {
            XCTFail(app.debugDescription)
            return false
        }
        let add = app.buttons["add-source"]
        reveal(add, in: app)
        add.tap()
        let name = app.textFields["source-name"]
        if !name.waitForExistence(timeout: 3), add.isHittable { add.tap() }
        guard name.waitForExistence(timeout: 10) else {
            XCTFail(app.debugDescription)
            return false
        }
        return true
    }

    func testIPTVExpiryFromProviderAppearsOnlyInSourceCard() {
        let laterLabels = ["Sonra", "Not Now", "Later"]
        let monitor = addUIInterruptionMonitor(withDescription: "Dismiss test password save prompt") { alert in
            let later = alert.buttons.matching(NSPredicate(format: "label IN %@", laterLabels)).firstMatch
            guard later.exists else { return false }
            later.tap(); return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        let scenarios = [
            ("active", false, "IPTV bitişi:", "2100"),
            ("expired", true, "IPTV süresi doldu:", "2023"),
            ("unknown", false, "Bitiş tarihi paylaşılmıyor", ""),
            ("error", false, "Bitiş tarihi alınamadı", "")
        ]
        for (scenario, xtream, prefix, year) in scenarios {
            let app = launch()
            guard openSourceEditor(in: app) else { app.terminate(); return }
            if xtream {
                app.buttons["source-kind"].tap()
                app.buttons["Xtream Codes"].tap()
                XCTAssertTrue(app.textFields["source-username"].waitForExistence(timeout: 5))
            }
            app.textFields["source-name"].tap()
            app.textFields["source-name"].typeText("IPTV QA")
            app.textFields["source-url"].tap()
            app.textFields["source-url"].typeText(xtream ? "http://127.0.0.1:8769/expiry/player_api.php" : "http://127.0.0.1:8769/expiry/get.php?username=expiry-\(scenario)&password=fixture&type=m3u_plus&output=ts")
            if xtream {
                app.textFields["source-username"].tap()
                app.textFields["source-username"].typeText("expiry-\(scenario)\n")
                let password = app.secureTextFields["source-password"]
                reveal(password, in: app)
                password.tap(); password.typeText("fixture")
            }
            app.buttons["Ekle"].tap()
            if xtream {
                let later = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", laterLabels)).firstMatch
                if later.waitForExistence(timeout: 5) { later.tap() }
                else {
                    let systemLater = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(NSPredicate(format: "label IN %@", laterLabels)).firstMatch
                    if systemLater.exists { systemLater.tap() }
                    else {
                        // iOS 26.5 sometimes omits the password prompt from the AX tree.
                        // In this fixed portrait fixture, this is the visible Later button;
                        // without the prompt it is empty space below the source card.
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.63)).tap()
                    }
                }
            }
            let expiry = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(expiry.waitForExistence(timeout: 15), app.debugDescription)
            if year.isEmpty { XCTAssertEqual(expiry.label, prefix) }
            else { XCTAssertTrue(expiry.label.contains(year)) }
            capture("iptv-expiry-\(scenario)-source", app: app)
            let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "IPTV QA", xtream ? "IPTV sunucusu" : "Oynatma listesi")).firstMatch
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            let channels = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tüm kanallar")).firstMatch
            if !channels.waitForExistence(timeout: 3), source.isHittable {
                source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            }
            XCTAssertTrue(channels.waitForExistence(timeout: 10), "Expiry metadata must not block channel loading")
            XCTAssertFalse(expiry.exists, "Keep account metadata on the source card, outside the channel browser")
            capture("iptv-expiry-\(scenario)-channels", app: app)
            app.terminate()
        }
    }

    func testDirectSourcePlaysAndLocalFileMethodOpensPicker() {
        let app = launch()
        guard openSourceEditor(in: app) else { return }
        app.buttons["source-kind"].tap()
        app.buttons["Yayın bağlantısı"].tap()
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Direct QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.mp4")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Direct QA", "Yayın bağlantısı")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let channel = app.buttons["Direct QA"].firstMatch
        if !channel.waitForExistence(timeout: 3), source.isHittable {
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        XCTAssertTrue(channel.waitForExistence(timeout: 10))
        channel.tap()
        XCTAssertTrue(app.buttons["Duraklat"].firstMatch.waitForExistence(timeout: 15))
        capture("direct-source-playing", app: app)
        app.terminate()

        let files = launch()
        guard openSourceEditor(in: files) else { return }
        files.buttons["source-kind"].tap()
        XCTAssertTrue(files.buttons["Dosyadan oynatma listesi"].waitForExistence(timeout: 5))
        files.buttons["Dosyadan oynatma listesi"].tap()
        XCTAssertFalse(files.textFields["source-url"].exists)
        XCTAssertFalse(files.buttons["Ekle"].isEnabled)
        capture("file-source-editor", app: files)
        files.buttons["source-file"].tap()
        let cancel = files.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Vazgeç", "İptal"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), files.debugDescription)
        capture("file-source-picker", app: files)
        cancel.tap()
        XCTAssertTrue(files.buttons["source-file"].waitForExistence(timeout: 5))
        files.terminate()
    }
    func testSettingsSecondaryScreensAndConnectionGuide() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["settings-quality"].waitForExistence(timeout: 5))
        func selectPreference(_ identifier: String, _ value: String) {
            let picker = app.buttons[identifier]
            picker.tap()
            let option = app.buttons[value]
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()
            // UIKit can publish menu items before the opening animation finishes.
            if !option.waitForNonExistence(timeout: 2) { option.tap() }
            XCTAssertTrue(option.waitForNonExistence(timeout: 3))
            XCTAssertTrue(picker.label.contains(value))
        }
        selectPreference("settings-quality", "Yüksek")
        selectPreference("settings-audio", "Kaynak uygulamadan")
        capture("audit-settings-preferences", app: app)
        for identifier in ["settings-notifications", "settings-language", "settings-vlc", "settings-cast", "settings-connection-test"] {
            reveal(app.buttons[identifier], in: app)
            app.buttons[identifier].tap()
            capture("audit-" + identifier, app: app)
            XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        // Restore the defaults changed by this UI-only audit.
        for _ in 0..<10 {
            if app.buttons["settings-quality"].isHittable { break }
            app.swipeDown()
        }
        selectPreference("settings-quality", "Dengeli")
        selectPreference("settings-audio", "Görüntüyle birlikte")
        reveal(app.buttons["settings-player-gesture-intro"], in: app)
        app.buttons["settings-player-gesture-intro"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        capture("audit-gesture-reset", app: app)
        app.alerts.buttons["Tamam"].tap()
        app.buttons["close-settings"].tap()
        reveal(app.buttons["tv-connection"], in: app)
        app.buttons["tv-connection"].tap()
        XCTAssertTrue(app.navigationBars["Ekran bağlantısı"].waitForExistence(timeout: 5))
        capture("audit-tv-picker", app: app)
        reveal(app.buttons["tv-connection-help"], in: app)
        app.buttons["tv-connection-help"].tap()
        for route in ["Google Cast", "AirPlay", "CarPlay"] {
            app.buttons["guide-" + route].tap()
            XCTAssertTrue(app.buttons["guide-" + route].isSelected)
            capture("audit-guide-" + route, app: app)
        }
        XCTAssertFalse(app.staticTexts["TV bulunamadı"].exists)
    }

    func testCarPlayStatusUsesVehicleLabelsAndFitsLargeText() {
        for videoSupported in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-carplay", "-AppleLanguages", "(tr)",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            if !videoSupported { app.launchArguments.append("-mirivo-ui-carplay-no-video") }
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let status = app.buttons["tv-route-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, "CarPlay")
            capture("audit-carplay-home-large", app: app)
            status.tap()
            let navigation = app.navigationBars["CarPlay"]
            if !navigation.waitForExistence(timeout: 3), status.isHittable { status.tap() }
            guard navigation.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
            let text = videoSupported
                ? "CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir."
                : "Bu araç CarPlay video oynatmayı desteklemiyor."
            reveal(app.staticTexts[text], in: app)
            XCTAssertTrue(app.staticTexts[text].isHittable)
            XCTAssertFalse(app.staticTexts["AirPlay ekranı"].exists)
            XCTAssertFalse(app.buttons["disconnect-tv-route"].exists)
            let disconnect = app.buttons["disconnect-carPlay-help"]
            reveal(disconnect, in: app)
            XCTAssertTrue(disconnect.isHittable)
            disconnect.tap()
            let help = app.alerts["Bağlantıyı kesme adımları"]
            if !help.waitForExistence(timeout: 3), disconnect.isHittable { disconnect.tap() }
            guard help.waitForExistence(timeout: 5) else {
                XCTFail(app.debugDescription)
                app.terminate()
                return
            }
            XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Kablolu CarPlay")).firstMatch.exists)
            capture("audit-carplay-disconnect-\(videoSupported)", app: app)
            app.alerts.buttons["Tamam"].tap()
            capture("audit-carplay-status-\(videoSupported)", app: app)
            app.buttons["Kapat"].tap()
            XCTAssertTrue(app.buttons["open-settings"].isHittable)
            if videoSupported {
                app.buttons["open-settings"].tap()
                app.buttons["settings-pro"].tap()
                let lifetime = app.buttons["pro-plan-com.alperbicer.carmirror.pro.lifetime"]
                XCTAssertTrue(lifetime.waitForExistence(timeout: 15))
                reveal(lifetime, in: app)
                let description = app.staticTexts["pro-description-com.alperbicer.carmirror.pro.lifetime"]
                XCTAssertGreaterThan(description.frame.width, app.frame.width * 0.6,
                                     "Large text descriptions must not be squeezed beside a fixed-width price")
                capture("audit-pro-large-text", app: app)
                reveal(app.buttons["pro-purchase"], in: app)
                XCTAssertTrue(app.buttons["pro-purchase"].isHittable)
                capture("audit-pro-purchase-large-text", app: app)
            }
            app.terminate()
        }
    }

    func testExternalCarPlayAndTVStatusOfferTheCorrectDisconnectSteps() {
        for carPlay in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-mirivo-ui-testing", carPlay ? "-mirivo-ui-carplay-display" : "-mirivo-ui-external-display",
                                   "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
            app.launch()
            let status = app.buttons["tv-route-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 10))
            XCTAssertEqual(status.label, carPlay ? "CarPlay" : "Harici ekran")
            capture(carPlay ? "route-carplay-home" : "route-tv-home", app: app)
            status.tap()
            let disconnect = app.buttons[carPlay ? "disconnect-carPlay-help" : "disconnect-externalDisplay-help"]
            if !disconnect.waitForExistence(timeout: 3), status.isHittable { status.tap() }
            XCTAssertTrue(disconnect.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[carPlay ? "CarPlay bağlı" : "Harici ekran"].exists)
            XCTAssertFalse(app.staticTexts["AirPlay ekranı"].exists)
            XCTAssertFalse(app.staticTexts["Bu araç CarPlay video oynatmayı desteklemiyor."].exists)
            capture(carPlay ? "route-carplay-status" : "route-tv-status", app: app)
            disconnect.tap()
            let alert = app.alerts["Bağlantıyı kesme adımları"]
            XCTAssertTrue(alert.waitForExistence(timeout: 3))
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", carPlay ? "CarPlay Simulator" : "Yansıtmayı Durdur")).firstMatch.exists)
            capture(carPlay ? "route-carplay-disconnect" : "route-tv-disconnect", app: app)
            app.terminate()
        }
    }

    func testConnectionStatusButtonMatchesHomeInChannelToolbar() {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-mirivo-ui-carplay-display", "-AppleLanguages", "(tr)",
                               "-AppleLocale", "tr_TR", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"]
        app.launch()
        defer { app.terminate() }
        let status = app.buttons["tv-route-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let homeSize = status.frame.size
        capture("route-toolbar-home", app: app)
        guard openSourceEditor(in: app) else { return }
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Route Toolbar QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/demo.m3u")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Route Toolbar QA")).firstMatch
        guard source.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tüm kanallar")).firstMatch
        if !all.waitForExistence(timeout: 3), source.isHittable {
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        let toolbarStatus = app.navigationBars.buttons["tv-route-status"]
        XCTAssertTrue(toolbarStatus.waitForExistence(timeout: 5))
        XCTAssertEqual(toolbarStatus.label, "CarPlay")
        XCTAssertEqual(toolbarStatus.frame.width, homeSize.width, accuracy: 1)
        XCTAssertEqual(toolbarStatus.frame.height, homeSize.height, accuracy: 1)
        capture("route-toolbar-channels", app: app)
        toolbarStatus.tap()
        XCTAssertTrue(app.buttons["disconnect-carPlay-help"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["AirPlay ekranı"].exists)
    }

    func testCarPlayAndExternalDisplayNamesStayConsistentAcrossHomePlayerAndMiniPlayer() {
        continueAfterFailure = false
        for carPlay in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-mirivo-ui-testing", carPlay ? "-mirivo-ui-carplay-display" : "-mirivo-ui-external-display",
                                   "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"]
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            let destination = carPlay ? "CarPlay" : "Harici ekran"
            let connection = app.buttons["tv-connection"]
            XCTAssertTrue(connection.waitForExistence(timeout: 10))
            XCTAssertEqual(connection.label, destination)
            XCTAssertFalse(app.staticTexts["TV’ye bağlan"].exists)
            capture("appwide-route-home-\(carPlay)", app: app)
            reveal(app.buttons["share-link"], in: app)
            app.buttons["share-link"].tap()
            let url = app.textFields["quick-media-url"]
            XCTAssertTrue(url.waitForExistence(timeout: 5))
            url.tap(); url.typeText("http://127.0.0.1:8769/tracks/options.mp4")
            app.buttons["quick-media-play"].tap()
            let output = app.staticTexts["player-output-destination"]
            XCTAssertTrue(output.waitForExistence(timeout: 15))
            XCTAssertEqual(output.label, destination)
            XCTAssertEqual(connection.label, destination)
            let pause = app.buttons["player-play-pause"]
            let playing = NSPredicate { _, _ in pause.exists && pause.label == "Duraklat" }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: playing, object: app)], timeout: 15), .completed)
            pause.tap()
            XCTAssertEqual(app.staticTexts["player-output-status"].label, "Yayın duraklatıldı")
            capture("appwide-route-player-\(carPlay)", app: app)
            connection.tap()
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["TV bağlantısı"].exists)
            let another = app.buttons["connect-another-display"]
            reveal(another, in: app)
            another.tap()
            let picker = app.navigationBars["Ekran bağlantısı"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["CarPlay"].exists)
            capture("appwide-route-picker-\(carPlay)", app: app)
            picker.buttons["Kapat"].tap()
            app.navigationBars[destination].buttons["Kapat"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let mini = app.buttons["now-playing-open"]
            XCTAssertTrue(mini.waitForExistence(timeout: 5))
            XCTAssertTrue(mini.label.contains(destination))
            app.buttons["Oynat"].tap()
            let expectedStatus = carPlay ? "Araç ekranında oynatılıyor" : "Harici ekranda oynatılıyor"
            XCTAssertTrue(app.staticTexts[expectedStatus].waitForExistence(timeout: 5))
            capture("appwide-route-mini-\(carPlay)", app: app)
            app.terminate()
        }
    }

    func testDisconnectedConnectionEntryUsesGenericDisplayLabels() {
        let app = launch()
        defer { app.terminate() }
        let connection = app.buttons["tv-connection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 10))
        XCTAssertEqual(connection.label, "Ekran bağlantısı")
        XCTAssertTrue(app.staticTexts["Ekrana bağlan"].exists)
        connection.tap()
        XCTAssertTrue(app.navigationBars["Ekran bağlantısı"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CarPlay"].exists)
        capture("appwide-route-disconnected-picker", app: app)
    }

    func testOfflineDownloadPlaybackAndRemoval() {
        let app = launch()
        defer { app.terminate() }
        guard openSourceEditor(in: app) else { return }
        app.buttons["source-kind"].tap(); app.buttons["Yayın bağlantısı"].tap()
        app.textFields["source-name"].tap(); app.textFields["source-name"].typeText("Offline QA")
        app.textFields["source-url"].tap(); app.textFields["source-url"].typeText("http://127.0.0.1:8769/tracks/options.mp4?offline=screen-audit")
        app.buttons["Ekle"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Offline QA", "Yayın bağlantısı")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let download = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "download-")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10)); download.tap()
        let finished = app.images["İndirildi"]
        XCTAssertTrue(finished.waitForExistence(timeout: 30))
        capture("audit-download-finished", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["offline-downloads-open"], in: app)
        app.buttons["offline-downloads-open"].tap()
        XCTAssertTrue(app.staticTexts["Çevrimdışı izlemeye hazır"].waitForExistence(timeout: 5))
        capture("audit-downloads", app: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "offline-item-")).firstMatch
        row.tap()
        XCTAssertTrue(app.otherElements["player-video"].waitForExistence(timeout: 10))
        capture("audit-offline-player", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Çevrimdışı izlemeye hazır"].waitForExistence(timeout: 5))
        row.swipeLeft(); app.buttons["Sil"].tap()
        XCTAssertTrue(app.staticTexts["Henüz indirilen içerik yok"].waitForExistence(timeout: 5))
        capture("audit-downloads-empty", app: app)
    }

    private func launch(language: String = "tr", large: Bool = false, continuations: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
        if continuations { app.launchArguments.append("-mirivo-ui-continue-watching") }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let portrait = NSPredicate { _, _ in app.frame.height > app.frame.width }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: app)], timeout: 30) == .completed)
        return app
    }
    func testAllShippingLanguagesLaunch() {
        assertLanguagesLaunch(shippingLanguages)
    }

    func testAddedLanguagesLaunch() {
        assertLanguagesLaunch(shippingLanguages.filter { ["ar", "he", "th", "vi", "id", "hi"].contains($0.0) })
    }

    private var shippingLanguages: [(String, String, String)] {
        [
            ("tr", "Ayarlar", "Ekranını paylaş"), ("en", "Settings", "Share your screen"),
            ("zh-Hans", "设置", "共享屏幕"), ("zh-Hant", "設定", "共享螢幕"),
            ("ja", "設定", "画面を共有"), ("ko", "설정", "화면 공유"),
            ("fr", "Réglages", "Partager l’écran"), ("de", "Einstellungen", "Bildschirm teilen"),
            ("es", "Ajustes", "Comparte tu pantalla"), ("it", "Impostazioni", "Condividi lo schermo"),
            ("pt-BR", "Ajustes", "Compartilhe sua tela"), ("ru", "Настройки", "Транслировать экран"),
            ("nl", "Instellingen", "Deel je scherm"), ("pl", "Ustawienia", "Udostępnij ekran"),
            ("sv", "Inställningar", "Dela skärmen"), ("uk", "Параметри", "Транслювати екран"),
            ("ar", "الإعدادات", "شارك شاشتك"), ("he", "הגדרות", "שיתוף המסך"),
            ("th", "การตั้งค่า", "แชร์หน้าจอของคุณ"), ("vi", "Cài đặt", "Chia sẻ màn hình"),
            ("id", "Pengaturan", "Bagikan layar Anda"), ("hi", "सेटिंग्स", "अपनी स्क्रीन शेयर करें")
        ]
    }

    private func assertLanguagesLaunch(_ labels: [(String, String, String)]) {
        for (language, settings, share) in labels {
            let app = launch(language: language)
            XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10), language)
            XCTAssertEqual(app.buttons["open-settings"].label, settings, language)
            XCTAssertTrue(app.staticTexts[share].exists, language)
            if ["de", "ja", "zh-Hant", "ru", "ar", "he", "th", "vi", "id", "hi"].contains(language) { capture("locale-\(language)", app: app) }
            app.terminate()
        }
    }

    func testRightToLeftSourceEntry() {
        let labels = [
            ("ar", "إضافة", "سياسة الخصوصية"),
            ("he", "הוספה", "מדיניות פרטיות")
        ]
        for (language, add, _) in labels {
            let app = launch(language: language)
            let settings = app.buttons["open-settings"]
            let mirror = app.buttons["page-mirror"]
            let library = app.buttons["page-library"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            XCTAssertGreaterThan(mirror.frame.midX, library.frame.midX, "\(language): navigation should mirror")
            library.tap()
            let selected = NSPredicate(format: "selected == true")
            if !selected.evaluate(with: library) { library.tap() }
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: library)], timeout: 5) == .completed, app.debugDescription)
            capture("rtl-library-entry-\(language)", app: app)
            reveal(app.buttons["add-source"], in: app)
            app.buttons["add-source"].tap()
            if !app.buttons["source-kind"].waitForExistence(timeout: 3) {
                app.buttons["add-source"].tap()
            }
            XCTAssertTrue(app.buttons["source-kind"].waitForExistence(timeout: 5))
            app.buttons["source-kind"].tap()
            app.buttons["Xtream Codes"].tap()
            let url = app.textFields["source-url"]
            XCTAssertTrue(url.waitForExistence(timeout: 5))
            let name = "QA RTL 1"
            app.textFields["source-name"].tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { app.textFields["source-name"].tap() }
            app.textFields["source-name"].typeText(name)
            let address = "https://example.com/live.m3u?user=qa&token=abc123"
            url.tap(); url.typeText(address)
            XCTAssertEqual(url.value as? String, address, "\(language): URL must remain intact")
            let username = app.textFields["source-username"]
            reveal(username, in: app)
            username.tap(); username.typeText("qa_user123")
            XCTAssertEqual(username.value as? String, "qa_user123")
            username.typeText("\n")
            let password = app.secureTextFields["source-password"]
            reveal(password, in: app)
            // Form fields can report hittable while covered by the pinned Add button.
            for _ in 0..<4 {
                if password.frame.maxY < app.buttons[add].frame.minY { break }
                let form = app.collectionViews.firstMatch
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                    .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
            }
            XCTAssertLessThan(password.frame.maxY, app.buttons[add].frame.minY)
            password.tap()
            password.typeText("qa_password123")
            capture("rtl-source-\(language)", app: app)
            app.buttons[add].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
            // iOS may offer to save the test credentials after the editor closes.
            let later = app.buttons.matching(NSPredicate(format: "label IN %@", ["Sonra", "Not Now", "Later"])).firstMatch
            if later.waitForExistence(timeout: 5) {
                for _ in 0..<3 {
                    later.tap()
                    let dismissed = NSPredicate(format: "exists == false")
                    if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: later)], timeout: 2) == .completed { break }
                }
                XCTAssertFalse(later.exists, "Dismiss the system password prompt before navigating")
            }
            capture("rtl-library-\(language)", app: app)
            app.terminate()
        }
    }

    func testRightToLeftWebsiteFallback() {
        for language in ["ar", "he"] {
            let app = launch(language: language)
            app.buttons["open-settings"].tap()
            openWebsite(app.buttons["settings-privacy"], heading: "Privacy Policy", app: app)
            app.terminate()
        }
    }

    func testNetlifyDocumentsOpenFromSettingsAndPro() {
        for language in ["tr", "en"] {
            let privacy = language == "tr" ? "Gizlilik Politikası" : "Privacy Policy"
            let terms = language == "tr" ? "Kullanım Koşulları (EULA)" : "Terms of Use (EULA)"
            let support = language == "tr" ? "Yardım ve SSS" : "Help & FAQ"
            let settingsApp = launch(language: language)
            settingsApp.buttons["open-settings"].tap()
            for (identifier, heading) in [("settings-privacy", privacy), ("settings-terms", terms), ("settings-support", support)] {
                openWebsite(settingsApp.buttons[identifier], heading: heading, app: settingsApp)
            }
            settingsApp.terminate()

            let proApp = launch(language: language)
            proApp.buttons["open-settings"].tap()
            XCTAssertTrue(proApp.buttons["settings-language"].waitForExistence(timeout: 10))
            let pro = proApp.descendants(matching: .any)["settings-pro"]
            for _ in 0..<8 {
                if pro.isHittable { break }
                proApp.swipeDown()
            }
            XCTAssertTrue(pro.waitForExistence(timeout: 10))
            pro.tap()
            for (identifier, heading) in [("pro-privacy", privacy), ("pro-terms", terms)] {
                openWebsite(proApp.buttons[identifier], heading: heading, app: proApp)
            }
            proApp.terminate()
        }
    }

    private func openWebsite(_ link: XCUIElement, heading: String, app: XCUIApplication) {
        reveal(link, in: app)
        let ready = NSPredicate { _, _ in link.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: link)], timeout: 10), .completed)
        link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(safari.webViews.staticTexts[heading].waitForExistence(timeout: 20), safari.debugDescription)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        capture("website-\(link.identifier)", app: safari)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func testRightToLeftLanguageSelectionPersistsAndReturnsToSystem() {
        let app = launch(language: "en")
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        app.buttons["open-settings"].tap()
        app.buttons["settings-language"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("ar")
        app.buttons["language-ar"].tap()
        XCTAssertTrue(app.navigationBars["اللغة"].waitForExistence(timeout: 5))
        capture("rtl-language-picker-ar", app: app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["open-settings"].label, "الإعدادات")
        XCTAssertGreaterThan(app.buttons["page-mirror"].frame.midX, app.buttons["page-library"].frame.midX)
        capture("rtl-relaunched-ar", app: app)
        app.buttons["open-settings"].tap()
        capture("rtl-reopened-settings-ar", app: app)
        XCTAssertTrue(app.buttons["settings-language"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["settings-language"].tap()
        app.buttons["language-system"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["close-settings"].tap()
        XCTAssertEqual(app.buttons["open-settings"].label, "Settings")
        XCTAssertLessThan(app.buttons["page-mirror"].frame.midX, app.buttons["page-library"].frame.midX)
    }

    func testLanguageSearchSwitchAndPersistence() {
        let app = launch(language: "en")
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        app.buttons["open-settings"].tap()
        app.buttons["settings-language"].tap()
        capture("language-picker", app: app)
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
        search.tap(); search.typeText("ja")
        let japanese = app.buttons["language-ja"].firstMatch
        XCTAssertTrue(japanese.waitForExistence(timeout: 5))
        capture("language-search", app: app)
        japanese.tap()
        XCTAssertTrue(app.buttons["language-ja"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["language-ja"].isSelected)
        // The first back action closes an active search before leaving the language list.
        for _ in 0..<2 {
            if app.buttons["settings-language"].exists { break }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.buttons["settings-language"].waitForExistence(timeout: 5), "Changing language should keep Settings open")
        capture("settings-ja", app: app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["open-settings"].label, "設定", "Explicit language persists across launches")
        app.buttons["open-settings"].tap()
        for identifier in ["settings-privacy", "settings-terms", "settings-support"] {
            reveal(app.buttons[identifier], in: app)
            XCTAssertTrue(app.buttons[identifier].isHittable)
        }
        capture("settings-links-ja", app: app)
        for _ in 0..<8 {
            if app.buttons["settings-language"].isHittable { break }
            app.swipeDown()
        }
        app.buttons["settings-language"].tap()
        app.buttons["language-system"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["close-settings"].tap()
        XCTAssertEqual(app.buttons["open-settings"].label, "Settings")
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    private func capture(_ name: String, app: XCUIApplication, waitForTransition: Bool = true) {
        // Capture the display: application-only cropping is unreliable after rotation.
        // Allow the compositor to finish sheet transitions before saving a visual reference.
        if waitForTransition { Thread.sleep(forTimeInterval: 0.4) }
        let screenshot = XCUIScreen.main.screenshot()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-\(name).png")
        try? screenshot.pngRepresentation.write(to: file)
        print("MIRIVO_UI_CAPTURE: \(file.path)")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTurkishProductAndSupportLinks() {
        let app = launch()
        XCTAssertTrue(app.buttons["page-mirror"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "open-settings").count, 1)
        XCTAssertGreaterThanOrEqual(app.buttons["page-mirror"].frame.height, 58)
        XCTAssertGreaterThanOrEqual(app.buttons["open-settings"].frame.height, 44)
        capture("01-mirivo-home-tr", app: app)
        app.buttons["page-library"].tap()
        XCTAssertTrue(app.staticTexts["Kaynakların burada"].waitForExistence(timeout: 5))
        capture("02-mirivo-sources-tr", app: app)
        let addSource = app.buttons["add-source"]
        reveal(addSource, in: app)
        XCTAssertGreaterThanOrEqual(addSource.frame.height, 58)
        addSource.tap()
        XCTAssertTrue(app.textFields["Kaynak adı"].waitForExistence(timeout: 5))
        app.textFields["Kaynak adı"].tap(); app.textFields["Kaynak adı"].typeText("QA List")
        app.textFields["Kaynak adresi"].tap(); app.textFields["Kaynak adresi"].typeText("https://example.com/list.m3u")
        capture("03-mirivo-add-source-tr", app: app)
        XCTAssertGreaterThanOrEqual(app.buttons["Ekle"].frame.height, 58)
        app.buttons["Ekle"].tap()
        XCTAssertTrue(app.staticTexts["QA List"].waitForExistence(timeout: 5))
        app.buttons["open-settings"].tap()
        capture("04-mirivo-settings-tr", app: app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Pro")).firstMatch.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            app.alerts.firstMatch.buttons["Tamam"].tap()
        }
        XCTAssertTrue(app.buttons["Satın alımları geri yükle"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Pro yakında"].exists)
        capture("05-mirivo-pro-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for identifier in ["settings-privacy", "settings-terms", "settings-support"] {
            reveal(app.buttons[identifier], in: app)
            XCTAssertTrue(app.buttons[identifier].isHittable)
        }
        reveal(app.buttons["Tüm kaynakları sil"], in: app)
        app.buttons["Tüm kaynakları sil"].tap()
        let confirm = app.buttons.matching(identifier: "Tüm kaynakları sil").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirm)
        confirm?.tap()
        app.buttons["close-settings"].tap()
        app.buttons["page-library"].tap()
        XCTAssertTrue(app.staticTexts["Kaynakların burada"].waitForExistence(timeout: 5))
    }
    func testProAnnualAndLifetimePlans() {
        for language in ["tr", "en"] {
            let app = launch(language: language)
            XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
            app.buttons["open-settings"].tap()
            let proSettings = app.buttons["settings-pro"]
            if !proSettings.waitForExistence(timeout: 3), app.buttons["open-settings"].exists {
                app.buttons["open-settings"].tap()
            }
            guard proSettings.waitForExistence(timeout: 10) else {
                XCTFail(app.debugDescription)
                app.terminate()
                return
            }
            // The settings sheet can enter AX before its transition completes.
            Thread.sleep(forTimeInterval: 0.8)
            proSettings.tap()
            let annual = app.buttons["pro-plan-com.alperbicer.carmirror.pro.yearly"]
            let lifetime = app.buttons["pro-plan-com.alperbicer.carmirror.pro.lifetime"]
            if !annual.waitForExistence(timeout: 3), proSettings.exists {
                proSettings.tap()
            }
            guard annual.waitForExistence(timeout: 20) else {
                XCTFail(app.debugDescription)
                app.terminate()
                return
            }
            XCTAssertTrue(lifetime.exists, app.debugDescription)
            XCTAssertFalse(app.buttons["pro-plan-com.alperbicer.carmirror.pro.weekly"].exists)
            XCTAssertTrue(annual.isSelected)
            XCTAssertTrue(lifetime.label.contains("49.99"), "StoreKit fixture must use the current lifetime price: \(lifetime.label)")
            reveal(app.buttons["pro-purchase"], in: app)
            capture("pro-plans-\(language)", app: app)
            reveal(lifetime, in: app)
            lifetime.tap()
            XCTAssertTrue(lifetime.isSelected)
            reveal(app.buttons["pro-purchase"], in: app)
            XCTAssertTrue(app.buttons["pro-purchase"].isEnabled)
            capture("pro-lifetime-\(language)", app: app)
            app.terminate()
        }
    }
    func testEnglishLargeTextKeepsHomePortraitAndControlsReachable() {
        let app = launch(language: "en", large: true)
        XCTAssertTrue(app.buttons["page-mirror"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Share your screen"].exists)
        capture("09-mirivo-large-text-en", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        // Only the player rotates; the home screen stays portrait on iPhone.
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
        // All controls remain reachable by scrolling at accessibility sizes.
        reveal(app.staticTexts["Share your screen"], in: app)
        capture("10-mirivo-large-text-share-en", app: app)
        XCTAssertTrue(app.staticTexts["Share your screen"].isHittable, app.debugDescription)
        app.swipeUp()
        capture("11-mirivo-large-text-scrolled-en", app: app)
        XCUIDevice.shared.orientation = .portrait
    }
}
