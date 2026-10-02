import XCTest

final class ProductUITests: XCTestCase {
    private func launch(language: String = "tr", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mirivo-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    func testAllShippingLanguagesLaunch() {
        let labels: [(String, String, String)] = [
            ("tr", "Ayarlar", "Ekranını paylaş"), ("en", "Settings", "Share your screen"),
            ("zh-Hans", "设置", "共享屏幕"), ("zh-Hant", "設定", "共享螢幕"),
            ("ja", "設定", "画面を共有"), ("ko", "설정", "화면 공유"),
            ("fr", "Réglages", "Partager l’écran"), ("de", "Einstellungen", "Bildschirm teilen"),
            ("es", "Ajustes", "Comparte tu pantalla"), ("it", "Impostazioni", "Condividi lo schermo"),
            ("pt-BR", "Ajustes", "Compartilhe sua tela"), ("ru", "Настройки", "Транслировать экран"),
            ("nl", "Instellingen", "Deel je scherm"), ("pl", "Ustawienia", "Udostępnij ekran"),
            ("sv", "Inställningar", "Dela skärmen"), ("uk", "Параметри", "Транслювати екран")
        ]
        for (language, settings, share) in labels {
            let app = launch(language: language)
            XCTAssertTrue(app.tabBars.buttons[settings].waitForExistence(timeout: 10), language)
            XCTAssertTrue(app.staticTexts[share].isHittable, language)
            if ["de", "ja", "zh-Hant", "ru"].contains(language) { capture("locale-\(language)", app: app) }
            app.terminate()
        }
    }

    func testLanguageSearchSwitchAndPersistence() {
        let app = launch(language: "en")
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings-language"].tap()
        capture("language-picker", app: app)
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 5) else { XCTFail(app.debugDescription); return }
        search.tap(); search.typeText("ja")
        let japanese = app.buttons["language-ja"].firstMatch
        XCTAssertTrue(japanese.waitForExistence(timeout: 5))
        capture("language-search", app: app)
        japanese.tap()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-language"].exists, "Changing language should keep the Settings tab")
        capture("settings-ja", app: app)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 10), "Explicit language persists across launches")
        app.tabBars.buttons["設定"].tap()
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
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
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
