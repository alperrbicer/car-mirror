import Foundation

/// Numeric App Store versions; never compare version strings lexicographically.
public struct AppVersion: Comparable, Sendable {
    private let components: [Int]
    public init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({
            !$0.isEmpty && $0.count <= 9 && $0.allSatisfy { $0.isASCII && $0.isNumber }
        }) else { return nil }
        components = parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct AppUpdatePolicy: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let enabled: Bool
    public let minimumVersion: String
    public let storeURL: String

    public init(schemaVersion: Int = 1, enabled: Bool, minimumVersion: String, storeURL: String) {
        self.schemaVersion = schemaVersion; self.enabled = enabled
        self.minimumVersion = minimumVersion; self.storeURL = storeURL
    }

    /// A missing/invalid policy or unknown current version must never lock a user out.
    public func requiredUpdateURL(currentVersion: String, appStoreID: String) -> URL? {
        guard schemaVersion == 1, enabled,
              let current = AppVersion(currentVersion), let minimum = AppVersion(minimumVersion), current < minimum,
              !appStoreID.isEmpty, appStoreID.allSatisfy({ $0.isASCII && $0.isNumber }),
              let url = URL(string: storeURL), url.scheme == "https", url.host == "apps.apple.com",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.pathComponents.contains("app"), url.lastPathComponent == "id" + appStoreID
        else { return nil }
        return url
    }
}

/// Push payloads may navigate only to these screens. They never open arbitrary URLs or media.
public enum NotificationRoute: String, Codable, Sendable, CaseIterable {
    case home, library, settings
}
