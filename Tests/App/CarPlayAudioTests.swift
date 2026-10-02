import XCTest
import AVFoundation
import MediaPlayer
@testable import CarMirror

@MainActor
final class CarPlayAudioTests: XCTestCase {
    func testAudioPlaybackPublishesAudioMetadataAndCleansUpControls() async throws {
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "Audio test", live: false, presentation: .audio)
        for _ in 0..<100 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
        XCTAssertEqual(AVAudioSession.sharedInstance().mode, .default)
        XCTAssertEqual(AVAudioSession.sharedInstance().routeSharingPolicy, .longFormAudio)
        let center = MPNowPlayingInfoCenter.default()
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Audio test")
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue,
                       MPNowPlayingInfoMediaType.audio.rawValue)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue, 0)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(MPRemoteCommandCenter.shared().stopCommand.isEnabled)
        playback.stop()
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(center.nowPlayingInfo)
        XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
        XCTAssertFalse(MPRemoteCommandCenter.shared().stopCommand.isEnabled)
    }

    func testSwitchingFromVideoToAudioDisablesExternalVideoAndUpdatesMetadata() throws {
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false, presentation: .video)
        XCTAssertTrue(playback.player.allowsExternalPlayback)
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false, presentation: .audio)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
        XCTAssertEqual((MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue,
                       MPNowPlayingInfoMediaType.audio.rawValue)
        XCTAssertEqual(AVAudioSession.sharedInstance().routeSharingPolicy, .longFormAudio)
    }

    private func audioFixture() throws -> URL {
        let samples = 44_100 * 10
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(36 + samples * 2)); text("WAVEfmt ")
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(44_100))
        word(UInt32(88_200)); word(UInt16(2)); word(UInt16(16)); text("data"); word(UInt32(samples * 2))
        for index in 0..<samples { word(Int16(sin(Double(index) * 2 * .pi * 440 / 44_100) * 1_000)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-audio-test-\(UUID()).wav")
        try data.write(to: url)
        return url
    }
}
