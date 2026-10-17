import Foundation

public enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "com.alperbicer.carmirror.pro.yearly"
    case weekly = "com.alperbicer.carmirror.pro.weekly"
    // Annual is the default offer.
    public static let forSale: [ProProduct] = [.yearly, .weekly]
}

/// A server-verified complimentary grant, separate from Apple's purchased products.
public struct ComplimentaryProGrant: Codable, Equatable, Sendable {
    public static let entitlementID = "mirivo_pro"
    // Keep offline access bounded so a revoked grant cannot remain active forever.
    public static let maximumOfflineAge: TimeInterval = 7 * 24 * 60 * 60
    public let customerID: String
    public let verifiedAt: Date
    public let expirationDate: Date

    public init(customerID: String, verifiedAt: Date, expirationDate: Date) {
        self.customerID = customerID
        self.verifiedAt = verifiedAt
        self.expirationDate = expirationDate
    }

    public func isActive(for customerID: String, at now: Date = Date()) -> Bool {
        !customerID.isEmpty && self.customerID == customerID
            && now >= verifiedAt.addingTimeInterval(-300)
            && now < verifiedAt.addingTimeInterval(Self.maximumOfflineAge)
            && now < expirationDate
    }
}

/// One policy for the phone, library and broadcast extension. Preparation builds
/// leave all features available; a configured storefront can enable the free tier.
public struct ProductAccess: Equatable, Sendable {
    public let salesEnabled: Bool
    public let verifiedPro: Bool
    public init(salesEnabled: Bool, verifiedPro: Bool) {
        self.salesEnabled = salesEnabled
        self.verifiedPro = verifiedPro
    }
    public var fullAccess: Bool { !salesEnabled || verifiedPro }
    // Source setup and browsing are available before subscribing. Playback,
    // downloads and broadcasting require a verified subscription or trial.
    public var sourceLimit: Int? { nil }
    public var broadcastLimit: TimeInterval? { nil }
    public func canAddSource(count: Int) -> Bool { sourceLimit.map { count < $0 } ?? true }
}

public enum StreamQuality: String, Codable, CaseIterable, Sendable {
    case balanced, high
    public var width: Int { self == .high ? 1280 : 960 }
    public var height: Int { self == .high ? 720 : 540 }
    public var framesPerSecond: Int { self == .high ? 30 : 20 }
    public var bitrate: Int { self == .high ? 3_600_000 : 1_800_000 }
}

public enum StreamAudioMode: String, Codable, CaseIterable, Sendable {
    case synchronized, source
}

public struct BroadcastOptions: Codable, Sendable {
    public var quality: StreamQuality = .balanced
    public var audioMode: StreamAudioMode = .synchronized
    public var captionsEnabled = false
    public var captionLocale = "tr-TR"
    public var durationLimit: TimeInterval?
    public init() {}
}
