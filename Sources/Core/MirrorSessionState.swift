import Foundation

public enum MirrorSessionState: String, Equatable, Sendable {
    case waitingForDisplay, ready, preparing, captureReady, connecting, presenting, paused, stopping, interrupted, failed

    public static func resolve(capture: CaptureStatus?, displayConnected: Bool, playbackSessionID: UUID?,
                               externalPlayback: Bool, playing: Bool, stopRequested: Bool,
                               playbackFailed: Bool, now: Date = Date()) -> Self {
        guard let capture else { return displayConnected ? .ready : .waitingForDisplay }
        if capture.phase == .failed { return .failed }
        if capture.phase == .stopped { return displayConnected ? .ready : .waitingForDisplay }
        guard capture.isFresh(at: now) else { return .interrupted }
        if stopRequested { return .stopping }
        if capture.phase == .paused { return .paused }
        if playbackFailed { return .failed }
        if capture.phase == .preparing || !capture.canPlay(at: now) { return .preparing }
        guard displayConnected, playbackSessionID == capture.sessionID else { return .captureReady }
        return externalPlayback && playing ? .presenting : .connecting
    }
}
