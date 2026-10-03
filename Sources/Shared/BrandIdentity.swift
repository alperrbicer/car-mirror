import Foundation

enum BrandIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mirivo"
    static let websiteURL = URL(string: "https://mirivo-support.netlify.app/")!
    static var tagline: String { L10n.tr("Telefonundan, aracına.") }
}
