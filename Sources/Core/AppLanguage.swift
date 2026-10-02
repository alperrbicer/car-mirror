import Foundation

/// App languages are independent of the speech models available on a device.
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case tr, en
    case simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case ja, ko, fr, de, es, it, brazilianPortuguese = "pt-BR"
    case ru, nl, pl, sv, uk
    case ar, he, th, vi, indonesian = "id", hi

    public var id: String { rawValue }
    public var isRightToLeft: Bool { ["ar", "he"].contains(rawValue) }
    public var nativeName: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        case .fr: "Français"
        case .de: "Deutsch"
        case .es: "Español"
        case .it: "Italiano"
        case .brazilianPortuguese: "Português (Brasil)"
        case .ru: "Русский"
        case .nl: "Nederlands"
        case .pl: "Polski"
        case .sv: "Svenska"
        case .uk: "Українська"
        case .ar: "العربية"
        case .he: "עברית"
        case .th: "ไทย"
        case .vi: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
        case .hi: "हिन्दी"
        }
    }

    public func matches(_ query: String, displayLocale: Locale) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let names = [nativeName, rawValue,
                     displayLocale.localizedString(forIdentifier: rawValue) ?? "",
                     Locale(identifier: "en").localizedString(forIdentifier: rawValue) ?? ""]
        return names.contains { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive], locale: displayLocale) != nil }
    }

    public static func resolve(selection: String, preferredLanguages: [String]) -> Self {
        if let selected = Self(rawValue: selection) { return selected }
        for identifier in preferredLanguages {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
            guard let code = parts.first else { continue }
            if code == "zh" {
                // An explicit script takes precedence over the region (zh-Hans-HK).
                if parts.contains("hans") { return .simplifiedChinese }
                if parts.contains("hant") || parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .traditionalChinese }
                return .simplifiedChinese
            }
            if code == "pt" { return .brazilianPortuguese }
            if let language = Self(rawValue: code) { return language }
        }
        return .en
    }
}
