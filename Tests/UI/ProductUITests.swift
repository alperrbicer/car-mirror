import XCTest

final class ProductUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch.waitForExistence(timeout: 10))
        if !playerOnly { capture("store-\(language)-02-channels", app: app) }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mirivo Demo 01")).firstMatch.tap()
        let pause = app.buttons[labels[3]].firstMatch
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
        XCTAssertTrue(home.buttons["guide-CarPlay"].waitForExistence(timeout: 10))
        home.buttons["guide-CarPlay"].tap()
        capture("store-\(language)-06-carplay", app: home)
        home.terminate()

        let editor = launch(language: language)
        guard openSourceEditor(in: editor) else { editor.terminate(); return }
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
    private func launch(language: String = "tr", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryM"]
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
            app.textFields["source-name"].tap(); app.textFields["source-name"].typeText(name)
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
        app.buttons["プライバシーポリシー"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Privacy Policy"].waitForExistence(timeout: 10), "Non-TR languages have a working English legal document")
        capture("legal-fallback-ja", app: app)
        app.webViews.links["Türkçe"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Gizlilik Politikası"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Türkçe"].isSelected)
        app.segmentedControls.buttons["English"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Privacy Policy"].waitForExistence(timeout: 10))
        app.webViews.links["Terms"].tap()
        XCTAssertTrue(app.navigationBars["利用規約（EULA）"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
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
    private func capture(_ name: String, app: XCUIApplication) {
        // Capture the display: application-only cropping is unreliable after rotation.
        // Allow the compositor to finish sheet transitions before saving a visual reference.
        Thread.sleep(forTimeInterval: 0.4)
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
    func testEnglishLayoutAndLargeTextLandscape() {
        let app = launch(language: "en", large: true)
        XCTAssertTrue(app.buttons["page-mirror"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Share your screen"].exists)
        capture("09-mirivo-large-text-en", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: rotated, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        // The entire page scrolls at accessibility sizes, including after rotation.
        reveal(app.staticTexts["Share your screen"], in: app)
        capture("10-mirivo-landscape-en", app: app)
        XCTAssertTrue(app.staticTexts["Share your screen"].isHittable, app.debugDescription)
        app.swipeUp()
        capture("11-mirivo-landscape-scrolled-en", app: app)
        XCUIDevice.shared.orientation = .portrait
    }
}
