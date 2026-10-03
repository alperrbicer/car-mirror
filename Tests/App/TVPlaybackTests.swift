import XCTest
import SwiftUI
@preconcurrency import GoogleCast
@testable import CarMirror

@MainActor
final class TVPlaybackTests: XCTestCase {
    func testDestinationSelectionSurvivesPickerClosingWithoutStartingPlayback() throws {
        let device = makeUnavailableDevice()
        let discovery = TVDiscovery()
        let playback = PlaybackController()
        defer { discovery.stop(); playback.stop() }
        discovery.start()
        try playback.setTVDevice(device)
        discovery.stop()
        XCTAssertEqual(playback.tvName, device.friendlyName)
        XCTAssertFalse(playback.hasActivePlayback, "Choosing a destination is not evidence of active playback")
        playback.stop()
        XCTAssertNotNil(playback.tvDevice, "A media stop/channel change must retain the selected destination")
        try playback.setTVDevice(nil)
        XCTAssertNil(playback.tvName)
        XCTAssertNil(playback.compatibility)
    }

    private func makeUnavailableDevice() -> GCKDevice {
        // SDK's public device factory isolates our state/connection tests from
        // Bonjour discovery, which requires a responding Cast receiver.
        let provider = GCKDeviceProvider(deviceCategory: kGCKCastDeviceCategory)
        let device = provider.createDevice(withID: UUID().uuidString,
                                          networkAddress: GCKNetworkAddress(type: .iPv4, ipAddress: "127.0.0.1"), servicePort: 9)
        device.friendlyName = "Mirivo Test TV"
        return device
    }

    func testHandoffPositionAndPausedIntentForNativeVideo() async throws {
        try await checkResume(useCompatibility: false)
    }

    func testUnavailableReceiverFailsWithoutClaimingActivePlayback() async throws {
        let device = makeUnavailableDevice()
        let playback = PlaybackController()
        defer { playback.stop(); try? playback.setTVDevice(nil) }
        try playback.setTVDevice(device)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false, live: false)
        for _ in 0..<700 {
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.state, .failed)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.hasActivePlayback)
        XCTAssertNotNil(playback.errorMessage)
    }

    func testHandoffPositionAndPausedIntentForCompatibilityVideo() async throws {
        try await checkResume(useCompatibility: true)
    }

    private func checkResume(useCompatibility: Bool) async throws {
        let playback = PlaybackController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIHostingController(rootView: MediaVideoView(playback: playback))
        window.makeKeyAndVisible()
        defer {
            playback.stop()
            window.isHidden = true; window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        let url = try XCTUnwrap(useCompatibility
            ? Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")
            : Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          live: false, useCompatibility: useCompatibility, startAt: 4, startPaused: true)
        for _ in 0..<200 {
            if playback.state == .paused, playback.currentTime > 3.8 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.state, .paused)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentTime, 4, accuracy: 0.6)
        let time = playback.currentTime
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(playback.currentTime, time, accuracy: 0.1)
        playback.resume()
        for _ in 0..<100 {
            if playback.isPlaying, playback.currentTime > 4.6 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.currentTime, 4.6)
    }

    func testExternalVideoOwnsSurfaceUntilTVDisconnects() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let root = try XCTUnwrap(window.rootViewController?.view)
        let engine = CompatibilityPlayback()
        let phone = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        phone.configure(engine: engine, role: .fullscreen, fillsFrame: true)
        root.addSubview(phone)
        let tv = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        tv.configure(engine: engine, role: .external, fillsFrame: false)
        root.addSubview(tv)
        phone.configure(engine: engine, role: .fullscreen, fillsFrame: true)
        XCTAssertTrue(engine.videoView.superview === tv)
        XCTAssertEqual(engine.videoView.bounds.size, tv.bounds.size)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .smaller)
        tv.removeFromSuperview()
        XCTAssertTrue(engine.videoView.superview === phone)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .larger)
    }
}
