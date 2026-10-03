import Foundation

public enum ProProduct: String, CaseIterable, Sendable {
    case weekly = "com.alperbicer.carmirror.pro.weekly"
    case yearly = "com.alperbicer.carmirror.pro.yearly"
    case lifetime = "com.alperbicer.carmirror.pro.lifetime"
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
    public var sourceLimit: Int? { fullAccess ? nil : 1 }
    public var broadcastLimit: TimeInterval? { fullAccess ? nil : 600 }
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

/// Device-local daily viewing budget. Intervals are split at local midnight.
public struct DailyViewingBudget: Codable, Equatable {
    public static let limit: TimeInterval = 2 * 60 * 60
    public private(set) var day: Date
    public private(set) var used: TimeInterval
    public init(now: Date, calendar: Calendar = .current, used: TimeInterval = 0) {
        day = calendar.startOfDay(for: now)
        self.used = max(0, used)
    }
    public mutating func record(from start: Date, to end: Date, playing: Bool, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: end)
        if today > day { day = today; used = 0 }
        guard playing, end > start else { return }
        used += max(0, end.timeIntervalSince(max(start, day)))
    }
    public var remaining: TimeInterval { max(0, Self.limit - used) }
}
