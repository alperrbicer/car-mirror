import Foundation

public enum MirrorSessionState: String, Equatable, Sendable {
    case waitingForCar, ready, preparing, captureReady, connecting, presenting, paused, stopping, interrupted, failed

    public static func resolve(capture: CaptureStatus?, carConnected: Bool, playbackSessionID: UUID?,
                               externalPlayback: Bool, playing: Bool, stopRequested: Bool,
                               playbackFailed: Bool, now: Date = Date()) -> Self {
        guard let capture else { return carConnected ? .ready : .waitingForCar }
        if capture.phase == .failed { return .failed }
        if capture.phase == .stopped { return carConnected ? .ready : .waitingForCar }
        guard capture.isFresh(at: now) else { return .interrupted }
        if stopRequested { return .stopping }
        if capture.phase == .paused { return .paused }
        if playbackFailed { return .failed }
        if capture.phase == .preparing || !capture.canPlay(at: now) { return .preparing }
        guard carConnected, playbackSessionID == capture.sessionID else { return .captureReady }
        return externalPlayback && playing ? .presenting : .connecting
    }
}
