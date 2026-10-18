import XCTest
import AVFoundation
import UIKit
@testable import CarMirror

@MainActor
final class PersonalMediaIntegrationTests: XCTestCase {
    func testCarPlayReceivesLocalVideoThroughHTTP() async throws {
        guard ProcessInfo.processInfo.environment["MIRIVO_TEST_CARPLAY_VIDEO"] == "1" else {
            throw XCTSkip("Requires a connected CarPlay video receiver")
        }
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let playback = PlaybackController()
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        var failures: [DiagnosticFailure] = []
        playback.onDiagnostic = { _, values in if let failure = values.failure { failures.append(failure) } }
        defer { playback.stop() }
        try playback.play(url: file, preserveSourceAudio: false, title: "CarPlay transport test", live: false)
        for _ in 0..<200 {
            if playback.state == .failed || playback.currentTime > 6 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotEqual(playback.state, .failed, playback.errorMessage ?? "")
        XCTAssertTrue(playback.player.isExternalPlaybackActive)
        XCTAssertGreaterThan(playback.currentTime, 6)
        XCTAssertTrue(failures.isEmpty, "Unexpected external playback failures: \(failures)")
        XCTAssertEqual((playback.player.currentItem?.asset as? AVURLAsset)?.url.scheme, "http")
    }

    func testCarPlayLocalVideoServesIdenticalBytesAndRevokesURLOnStop() async throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        try playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                          live: false, startPaused: true)
        let item = try await nativeItem(playback)
        let address = try XCTUnwrap((item.asset as? AVURLAsset)?.url)
        XCTAssertEqual(address.scheme, "http")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.data(from: address)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, try Data(contentsOf: file), "The receiver must get the original media, without transcoding")
        playback.stop()
        XCTAssertNil(playback.player.currentItem)
        do { _ = try await session.data(from: address); XCTFail("Stop must revoke the receiver URL") }
        catch { }
    }

    func testCancelledCarPlayPreparationCannotReplacePhonePlayback() async throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        for _ in 0..<5 {
            playback.setPlaysOnPhone(false)
            try playback.play(url: file, preserveSourceAudio: false, live: false)
            playback.stop()
        }
        playback.setPlaysOnPhone(true)
        try playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                          live: false, startPaused: true)
        let replacement = try XCTUnwrap(playback.player.currentItem)
        let id = playback.playbackID
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(playback.player.currentItem === replacement)
        XCTAssertEqual(playback.playbackID, id)
        XCTAssertEqual((replacement.asset as? AVURLAsset)?.url, file)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
    }

    func testCarPlayKeepsPhoneAudioAndOwnedDisplayFilesLocal() throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        for (phone, ownedDisplay, presentation) in [(true, false, MediaPlaybackPresentation.video),
                                                   (false, true, .video), (false, false, .audio)] {
            let playback = PlaybackController()
            defer { playback.stop() }
            playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
            playback.setPlaysOnPhone(phone)
            playback.externalDisplayConnected = ownedDisplay
            try playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                              live: false, presentation: presentation, startPaused: true)
            let item = try XCTUnwrap(playback.player.currentItem)
            XCTAssertEqual((item.asset as? AVURLAsset)?.url, file)
            XCTAssertFalse(playback.player.allowsExternalPlayback)
        }
    }

    func testCarPlayVideoCapabilityControlsLocalFileTransport() async throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let model = MirrorModel(viewingAccess: { ProductAccess(salesEnabled: true, verifiedPro: true) }, startsTimer: false)
        defer { model.stopPlayback(); model.disconnected() }
        // An audio-only or unknown CarPlay session must not add an HTTP/network
        // requirement to ordinary phone playback, including after a video session.
        for capability: Bool? in [true, false, nil] {
            model.connected(supportsVideo: capability)
            try model.playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                                    live: false, startPaused: true)
            let item = try await nativeItem(model.playback)
            XCTAssertEqual((item.asset as? AVURLAsset)?.url.scheme, capability == true ? "http" : "file")
        }
        model.disconnected()
        try model.playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                                live: false, startPaused: true)
        XCTAssertEqual((model.playback.player.currentItem?.asset as? AVURLAsset)?.url, file)
    }

    func testCarPlayLocalVideoPreservesPausedSeekAndPhoneHandoff() async throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        try playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                          live: false, startAt: 3, startPaused: true)
        let item = try await nativeItem(playback)
        for _ in 0..<100 where playback.state != .paused {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.state, .paused)
        XCTAssertEqual(playback.currentTime, 3, accuracy: 0.3)
        let id = playback.playbackID
        playback.setPlaysOnPhone(true)
        XCTAssertTrue(playback.player.currentItem === item)
        XCTAssertEqual(playback.playbackID, id)
        playback.setPlaysOnPhone(false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(playback.player.currentItem === item)
        XCTAssertEqual(playback.playbackID, id)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentTime, 3, accuracy: 0.3)
    }

    func testExternalRejectionRecoversLocalFileOnceAndPreservesPosition() async throws {
        let file = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let playback = PlaybackController()
        defer { playback.stop() }
        var failures = 0
        playback.onFailure = { _ in failures += 1 }
        // The file was opened on the phone before a receiver was selected.
        try playback.play(url: file, preserveSourceAudio: false, requiresExternalPlayback: false,
                          live: false, startAt: 4, startPaused: true)
        let original = try XCTUnwrap(playback.player.currentItem)
        XCTAssertEqual((original.asset as? AVURLAsset)?.url, file)
        let rejection = NSError(domain: AVFoundationErrorDomain,
                                code: AVError.externalPlaybackNotSupportedForAsset.rawValue)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: original,
                                        userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: rejection])
        for _ in 0..<100 {
            if let current = playback.player.currentItem, current !== original, playback.state == .paused { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let recovered = try XCTUnwrap(playback.player.currentItem)
        XCTAssertFalse(recovered === original)
        XCTAssertEqual((recovered.asset as? AVURLAsset)?.url.scheme, "http")
        XCTAssertEqual(playback.state, .paused)
        XCTAssertEqual(playback.currentTime, 4, accuracy: 0.3)
        XCTAssertEqual(failures, 0)
        // If the receiver also rejects HTTP, surface the failure instead of looping.
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: recovered,
                                        userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: rejection])
        for _ in 0..<100 where playback.state != .failed { await Task.yield() }
        XCTAssertEqual(playback.state, .failed)
        XCTAssertNil(playback.player.currentItem)
        XCTAssertEqual(failures, 1)
    }

    private func nativeItem(_ playback: PlaybackController) async throws -> AVPlayerItem {
        for _ in 0..<100 where playback.player.currentItem == nil && playback.state != .failed {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(playback.player.currentItem, playback.errorMessage ?? "Missing native video item")
    }

    func testLocalCastingAndFullscreenDoNotReleaseEachOthersScreenLock() {
        let previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = false
        defer { UIApplication.shared.isIdleTimerDisabled = previous }
        let casting = MediaScreenAwake.acquire()
        let fullscreen = MediaScreenAwake.acquire()
        MediaScreenAwake.release(fullscreen)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        MediaScreenAwake.release(casting)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }
    func testFileCopyPreservesOriginalAndCleansOnlyOwnedCopies() throws {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        let data = Data("User-selected media".utf8)
        try data.write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }
        let copy = try PersonalMediaFiles.copy(original)
        XCTAssertEqual(try Data(contentsOf: copy), data)
        PersonalMediaFiles.remove([copy, original])
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try Data(contentsOf: original), data)
    }

    func testImportedAudioQueueAdvancesAndStopsAfterLastTrack() async throws {
        let model = MirrorModel(viewingAccess: { ProductAccess(salesEnabled: true, verifiedPro: true) }, startsTimer: false)
        model.stopBroadcast()
        let urls = (0..<2).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav") }
        defer { model.stopPlayback(); urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        for index in 0..<44100 { buffer.floatChannelData?[0][index] = 0 }
        for url in urls {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let channels = urls.enumerated().map { MediaChannel(title: "Track \($0.offset + 1)", url: $0.element) }
        XCTAssertTrue(model.playMedia(channels[0], queue: channels, advanceAutomatically: true))
        var reachedSecond = false
        for _ in 0..<160 {
            if model.selectedMediaChannel == channels[1] { reachedSecond = true }
            if reachedSecond && model.selectedMediaChannel == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(reachedSecond)
        XCTAssertNil(model.selectedMediaChannel)
        XCTAssertFalse(model.playback.hasActivePlayback)
    }

    func testSlideshowProducesPlayable1080pVideoWithOrderedPhotos() async throws {
        let originals = try [UIColor.red, UIColor.blue].map { color in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
            }
            try XCTUnwrap(image.pngData()).write(to: url)
            return url
        }
        defer { originals.forEach { try? FileManager.default.removeItem(at: $0) } }
        let output = try await PhotoSlideshow.export(originals, secondsPerPhoto: 3) { _ in }
        defer { PersonalMediaFiles.remove([output]) }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 6, accuracy: 0.1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1920, height: 1080))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 30)).image
        let second = try await generator.image(at: CMTime(seconds: 4, preferredTimescale: 30)).image
        let red = centerPixel(first), blue = centerPixel(second)
        XCTAssertGreaterThan(red[0], 220); XCTAssertLessThan(red[2], 30)
        XCTAssertGreaterThan(blue[2], 220); XCTAssertLessThan(blue[0], 30)
        let playback = PlaybackController()
        defer { playback.stop() }
        try playback.play(url: output, preserveSourceAudio: false, requiresExternalPlayback: false, live: false)
        for _ in 0..<100 {
            if playback.isPlaying && playback.currentTime > 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.currentTime, 0)
        XCTAssertFalse(playback.isLive)
    }

    func testCancelledSlideshowDoesNotReturnAnOutput() async throws {
        let task = Task { try await PhotoSlideshow.export([URL(fileURLWithPath: "/missing.png")], secondsPerPhoto: 3) { _ in } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled export returned a file") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testLocalServerSupportsRangesHeadAndRejectsOtherPaths() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let data = Data((0..<200_000).map { UInt8($0 % 251) })
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = try PersonalMediaServer(file: file)
        defer { server.stop() }
        let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            // Only the first listener event resolves the continuation.
            let completion = ServerStartCompletion(continuation)
            server.start(host: "127.0.0.1", onReady: { completion.finish(.success($0)) },
                         onFailure: { completion.finish(.failure(PersonalMediaError.unreadable)) })
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (full, response) = try await session.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(full, data)
        var request = URLRequest(url: url)
        request.setValue("bytes=123-999", forHTTPHeaderField: "Range")
        let (part, partialResponse) = try await session.data(for: request)
        let http = try XCTUnwrap(partialResponse as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 123-999/200000")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        XCTAssertEqual(part, data.subdata(in: 123..<1000))
        request.setValue("bytes=-12", forHTTPHeaderField: "Range")
        let (suffix, _) = try await session.data(for: request)
        XCTAssertEqual(suffix, data.suffix(12))
        request.httpMethod = "HEAD"
        let (head, headResponse) = try await session.data(for: request)
        XCTAssertTrue(head.isEmpty)
        XCTAssertEqual((headResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"), "12")
        request.httpMethod = "GET"
        request.setValue("bytes=200000-", forHTTPHeaderField: "Range")
        let (_, invalid) = try await session.data(for: request)
        XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 416)
        let (_, unknown) = try await session.data(from: url.deletingLastPathComponent().appendingPathComponent("another.mp4"))
        XCTAssertEqual((unknown as? HTTPURLResponse)?.statusCode, 404)
        request.httpMethod = "OPTIONS"
        request.setValue(nil, forHTTPHeaderField: "Range")
        let (preflightBody, preflight) = try await session.data(for: request)
        XCTAssertEqual((preflight as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertEqual((preflight as? HTTPURLResponse)?.value(forHTTPHeaderField: "Access-Control-Allow-Headers"), "Range")
        XCTAssertTrue(preflightBody.isEmpty)
        server.stop()
        do { _ = try await session.data(from: url); XCTFail("Stopped server still served a file") }
        catch { /* Revoking playback must revoke the URL. */ }
    }

    private func centerPixel(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { memory in
            let context = CGContext(data: memory.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        }
        return bytes
    }
}

private final class ServerStartCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }
    func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
