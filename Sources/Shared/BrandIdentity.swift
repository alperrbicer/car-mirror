import Foundation

enum BrandIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mirivo"
    static var tagline: String { L10n.tr("Telefonundan, aracına.") }
}
