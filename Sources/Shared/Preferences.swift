import Foundation

enum SharedPreferences {
    static var defaults: UserDefaults {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "CMAppGroupIdentifier") as? String,
              let defaults = UserDefaults(suiteName: identifier) else { return .standard }
        return defaults
    }
    static var salesEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "CMProPurchasesEnabled") as? String == "YES" }
    static func options() -> BroadcastOptions {
        var result = BroadcastOptions()
        result.quality = StreamQuality(rawValue: defaults.string(forKey: "streamQuality") ?? "") ?? .balanced
        result.audioMode = StreamAudioMode(rawValue: defaults.string(forKey: "audioMode") ?? "") ?? .synchronized
        result.captionsEnabled = defaults.bool(forKey: "captionsEnabled")
        result.captionLocale = defaults.string(forKey: "captionLocale") ?? "tr-TR"
        // Written by verified StoreKit entitlements, never by a user-facing switch.
        let access = ProductAccess(salesEnabled: salesEnabled, verifiedPro: defaults.bool(forKey: "verifiedPro"))
        result.durationLimit = access.broadcastLimit
        if !access.fullAccess { result.captionsEnabled = false }
        return result
    }
}

enum L10n {
    static var appLanguage: AppLanguage {
        let preferred = SharedPreferences.defaults.string(forKey: "language") ?? "system"
        return AppLanguage.resolve(selection: preferred, preferredLanguages: Locale.preferredLanguages)
    }
    static var language: String { appLanguage.rawValue }
    // Shared by the app and ReplayKit extension; resource bundles do not change at runtime.
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language.rawValue, bundle)
    })
    static func tr(_ key: String) -> String {
        let fallback = bundles["en"]?.localizedString(forKey: key, value: key, table: nil) ?? key
        return bundles[language]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    }
}
