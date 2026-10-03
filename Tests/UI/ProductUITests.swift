import XCTest

final class ProductUITests: XCTestCase {
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

    func testRightToLeftLegalFallback() {
        for (language, privacy) in [("ar", "سياسة الخصوصية"), ("he", "מדיניות פרטיות")] {
            let app = launch(language: language)
            app.buttons["open-settings"].tap()
            XCTAssertTrue(app.buttons["settings-language"].waitForExistence(timeout: 5))
            capture("rtl-settings-\(language)", app: app)
            let form = app.collectionViews.firstMatch
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            let link = app.buttons[privacy]
            reveal(link, in: app)
            link.tap()
            if !app.webViews.firstMatch.waitForExistence(timeout: 3), link.exists { link.tap() }
            XCTAssertTrue(app.webViews.staticTexts["Privacy Policy"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.segmentedControls.buttons["English"].isSelected)
            capture("rtl-legal-\(language)", app: app)
            app.terminate()
        }
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
    func testTurkishProductAndOfflineLegalFlows() {
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
        XCTAssertTrue(app.staticTexts["Pro yakında"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Satın al")).firstMatch.exists)
        capture("05-mirivo-pro-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["Gizlilik Politikası"], in: app)
        app.buttons["Gizlilik Politikası"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["Gizlilik Politikası"].waitForExistence(timeout: 10))
        capture("06-mirivo-privacy-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["Kullanım Koşulları (EULA)"], in: app)
        app.buttons["Kullanım Koşulları (EULA)"].tap()
        XCTAssertTrue(app.webViews.links["Apple Standart EULA ↗"].waitForExistence(timeout: 10))
        capture("07-mirivo-terms-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["Yardım ve SSS"], in: app)
        app.buttons["Yardım ve SSS"].tap()
        XCTAssertTrue(app.webViews.links["Destek için yaz ↗"].waitForExistence(timeout: 10))
        capture("08-mirivo-help-tr", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["Tüm kaynakları sil"], in: app)
        app.buttons["Tüm kaynakları sil"].tap()
        let confirm = app.buttons.matching(identifier: "Tüm kaynakları sil").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirm)
        confirm?.tap()
        app.buttons["close-settings"].tap()
        app.buttons["page-library"].tap()
        XCTAssertTrue(app.staticTexts["Kaynakların burada"].waitForExistence(timeout: 5))
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
