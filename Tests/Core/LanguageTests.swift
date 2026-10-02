import XCTest
@testable import MirrorCore

final class LanguageTests: XCTestCase {
    func testRegionalPreferencesAndFallback() {
        let cases: [([String], AppLanguage)] = [
            (["de-DE"], .de), (["fr-CA"], .fr), (["es-MX"], .es),
            (["pt-PT"], .brazilianPortuguese), (["pt_BR"], .brazilianPortuguese),
            (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese),
            (["zh-MO"], .traditionalChinese), (["zh-Hans-HK"], .simplifiedChinese),
            (["zh-Hant-CN"], .traditionalChinese), (["zh-SG"], .simplifiedChinese),
            (["ar-SA"], .ar), (["he-IL"], .he), (["th-TH"], .th),
            (["vi-VN"], .vi), (["id-ID"], .indonesian), (["hi-IN"], .hi),
            (["no-NO", "uk-UA"], .uk), (["unknown"], .en), ([], .en)
        ]
        for (preferences, expected) in cases {
            XCTAssertEqual(AppLanguage.resolve(selection: "system", preferredLanguages: preferences), expected, "\(preferences)")
        }
        XCTAssertEqual(AppLanguage.resolve(selection: "ja", preferredLanguages: ["tr-TR"]), .ja)
        XCTAssertEqual(AppLanguage.resolve(selection: "deleted-language", preferredLanguages: ["de-DE"]), .de)
        for language in [AppLanguage.ar, .he, .th, .vi, .indonesian, .hi] {
            XCTAssertEqual(AppLanguage.resolve(selection: language.rawValue, preferredLanguages: ["en-US"]), language)
        }
    }

    func testLanguageSearchUsesNativeLocalizedNamesAndCodes() {
        XCTAssertTrue(AppLanguage.fr.matches("francais", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.de.matches("Almanca", displayLocale: Locale(identifier: "tr")))
        XCTAssertTrue(AppLanguage.ja.matches("日本", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.brazilianPortuguese.matches("pt-BR", displayLocale: Locale(identifier: "tr")))
        XCTAssertTrue(AppLanguage.simplifiedChinese.matches("Simplified", displayLocale: Locale(identifier: "tr")))
        XCTAssertTrue(AppLanguage.uk.matches("  ", displayLocale: Locale(identifier: "tr")))
        XCTAssertFalse(AppLanguage.ko.matches("unknown-language", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.ar.matches("العربية", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.he.matches("עברית", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.th.matches("Thai", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.vi.matches("tieng viet", displayLocale: Locale(identifier: "en")))
        XCTAssertTrue(AppLanguage.indonesian.matches("Endonezce", displayLocale: Locale(identifier: "tr")))
        XCTAssertTrue(AppLanguage.hi.matches("Hindi", displayLocale: Locale(identifier: "en")))
    }

    func testShippingCatalogIncludesAllTwentyTwoLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configured = try JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("Config/Localizations.json")))
        XCTAssertEqual(Set(configured), Set(AppLanguage.allCases.map(\.rawValue)))
        XCTAssertEqual(configured.count, 22)
        XCTAssertTrue(Set(["ar", "he", "th", "vi", "id", "hi"]).isSubset(of: Set(configured)))
    }

    func testOnlyArabicAndHebrewUseRightToLeftLayout() {
        XCTAssertEqual(Set(AppLanguage.allCases.filter(\.isRightToLeft).map(\.rawValue)), ["ar", "he"])
    }
}
