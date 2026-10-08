import XCTest
@testable import MirrorCore

final class MirrorSessionStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 500)

    private func liveCapture() -> CaptureStatus {
        var status = CaptureStatus(phase: .live, updatedAt: now)
        status.segmentCount = 3
        status.loopbackURL = URL(string: "http://127.0.0.1:1234/example/stream.m3u8")
        return status
    }

    private func state(_ capture: CaptureStatus?, car: Bool = true, session: UUID? = nil,
                       external: Bool = false, playing: Bool = false, stopping: Bool = false, failed: Bool = false) -> MirrorSessionState {
        .resolve(capture: capture, displayConnected: car, playbackSessionID: session, externalPlayback: external,
                 playing: playing, stopRequested: stopping, playbackFailed: failed, now: now)
    }

    func testCaptureReadinessDoesNotClaimExternalPresentation() {
        let capture = liveCapture()
        XCTAssertEqual(state(capture), .captureReady)
        XCTAssertEqual(state(capture, session: capture.sessionID, playing: true), .connecting)
        XCTAssertEqual(state(capture, session: capture.sessionID, external: true), .connecting)
        XCTAssertEqual(state(capture, session: capture.sessionID, external: true, playing: true), .presenting)
    }

    func testOldSessionOrDisconnectedCarCannotClaimPresentation() {
        let capture = liveCapture()
        XCTAssertEqual(state(capture, session: UUID(), external: true, playing: true), .captureReady)
        XCTAssertEqual(state(capture, car: false, session: capture.sessionID, external: true, playing: true), .captureReady)
    }

    func testStoppingAndStaleCaptureTakePrecedenceOverPlayerSignals() {
        var capture = liveCapture()
        XCTAssertEqual(state(capture, session: capture.sessionID, external: true, playing: true, stopping: true), .stopping)
        capture.updatedAt = now.addingTimeInterval(-7)
        XCTAssertEqual(state(capture, session: capture.sessionID, external: true, playing: true), .interrupted)
    }

    func testPauseFailureAndFinishRemainDistinct() {
        var capture = liveCapture()
        capture.phase = .paused
        XCTAssertEqual(state(capture), .paused)
        capture.phase = .failed
        XCTAssertEqual(state(capture), .failed)
        capture.phase = .stopped
        XCTAssertEqual(state(capture), .ready)
        XCTAssertEqual(state(capture, car: false), .waitingForDisplay)
        XCTAssertEqual(state(nil, car: false), .waitingForDisplay)
    }
}
