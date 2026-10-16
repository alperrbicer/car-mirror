import Foundation

public enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "com.alperbicer.carmirror.pro.yearly"
    case lifetime = "com.alperbicer.carmirror.pro.lifetime"

    // Keep lifetime entitlements restorable, but offer only the annual membership.
    public static let forSale: [ProProduct] = [.yearly]
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
