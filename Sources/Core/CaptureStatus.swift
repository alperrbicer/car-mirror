import Foundation

public enum CapturePhase: String, Codable, Sendable {
    case preparing, live, paused, stopped, failed
}

public struct CaptureStatus: Codable, Equatable, Sendable {
    public var sessionID: UUID
    public var phase: CapturePhase
    public var updatedAt: Date
    public var receivedFrames: Int = 0
    public var encodedFrames: Int = 0
    public var droppedFrames: Int = 0
    public var segmentCount: Int = 0
    public var bufferedBytes: Int = 0
    public var loopbackURL: URL?
    public var networkURL: URL?
    public var message: String?

    public init(sessionID: UUID = UUID(), phase: CapturePhase = .preparing, updatedAt: Date = Date()) {
        self.sessionID = sessionID
        self.phase = phase
        self.updatedAt = updatedAt
    }

    public func isFresh(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age >= -2 && age < 6
    }

    public func canPlay(at now: Date = Date()) -> Bool {
        phase == .live && isFresh(at: now) && segmentCount >= 3 && loopbackURL != nil
    }
}

public struct CaptureCommand: Codable, Sendable {
    public var sessionID: UUID
    public var action: String
    public init(stop sessionID: UUID) {
        self.sessionID = sessionID
        action = "stop"
    }
}
