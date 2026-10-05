import Foundation

enum BrandIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mirivo"
    static let websiteURL = URL(string: "https://mirivo-support.netlify.app/")!
    static var privacyURL: URL { pageURL("privacy") }
    static var termsURL: URL { pageURL("terms") }
    static var supportURL: URL { pageURL("support") }
    private static func pageURL(_ page: String) -> URL {
        websiteURL.appendingPathComponent(L10n.language == "tr" ? "tr" : "en")
            .appendingPathComponent("\(page).html")
    }
    static var tagline: String { L10n.tr("Telefonundan, aracına.") }
}
