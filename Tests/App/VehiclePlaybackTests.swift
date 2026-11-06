import XCTest
import SwiftUI
import AVFoundation
import CoreImage
import CarPlay
import Combine
@testable import CarMirror

@MainActor
final class PerformanceRegressionTests: XCTestCase {
    func testArtworkDiskCacheSurvivesRelaunchExpiresAndClears() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = "https://example.invalid/poster.jpg?password=private"
        let data = Data([1, 2, 3]), now = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = MediaArtworkDiskCache(directory: directory, lifetime: 60)
        await cache.store(data, forKey: key, now: now)
        let relaunched = MediaArtworkDiskCache(directory: directory, lifetime: 60)
        let restored = await relaunched.data(forKey: key, now: now.addingTimeInterval(1))
        XCTAssertEqual(restored, data)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.allSatisfy { $0.range(of: "^[a-f0-9]{64}\\.artwork$", options: .regularExpression) != nil })
        let expired = await relaunched.data(forKey: key, now: now.addingTimeInterval(61))
        XCTAssertNil(expired)
        await relaunched.store(data, forKey: key)
        let current = await relaunched.data(forKey: key)
        XCTAssertEqual(current, data)
        await relaunched.removeAll()
        let cleared = await relaunched.data(forKey: key, now: now.addingTimeInterval(1))
        XCTAssertNil(cleared)
    }

    func testArtworkDiskCacheBoundsStorageAndIgnoresUnavailableDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = MediaArtworkDiskCache(directory: directory, maximumBytes: 6, maximumEntries: 2)
        await cache.store(Data(repeating: 1, count: 4), forKey: "old", now: now)
        await cache.store(Data(repeating: 2, count: 4), forKey: "new", now: now.addingTimeInterval(1))
        await cache.store(Data(repeating: 3, count: 7), forKey: "oversized", now: now.addingTimeInterval(2))
        let old = await cache.data(forKey: "old", now: now.addingTimeInterval(3))
        let new = await cache.data(forKey: "new", now: now.addingTimeInterval(3))
        let oversized = await cache.data(forKey: "oversized", now: now.addingTimeInterval(3))
        XCTAssertNil(old)
        XCTAssertEqual(new, Data(repeating: 2, count: 4))
        XCTAssertNil(oversized)
        await cache.removeAll()
        for index in 0..<3 {
            await cache.store(Data([UInt8(index)]), forKey: "entry-\(index)", now: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        let evicted = await cache.data(forKey: "entry-0", now: now.addingTimeInterval(3))
        XCTAssertNil(evicted)
        await cache.removeAll()
        try Data([0]).write(to: directory)
        await cache.store(Data([1]), forKey: "unavailable", now: now)
        let unavailable = await cache.data(forKey: "unavailable", now: now.addingTimeInterval(1))
        XCTAssertNil(unavailable)
    }

    func testArtworkRequestsShareWorkAndOneCancellationKeepsOtherReaders() async throws {
        var requests = 0
        var finish: CheckedContinuation<UIImage?, Never>?
        let image = try XCTUnwrap(UIImage(systemName: "film"))
        let store = MediaArtworkStore { _, _, _ in
            requests += 1
            return await withCheckedContinuation { finish = $0 }
        }
        let url = URL(string: "https://example.invalid/poster.jpg")!
        let first = Task { await store.image(at: url) }
        let second = Task { await store.image(at: url) }
        for _ in 0..<100 where finish == nil { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        first.cancel()
        try XCTUnwrap(finish).resume(returning: image)
        let cancelled = await first.value
        let shown = await second.value
        XCTAssertNil(cancelled)
        XCTAssertTrue(shown === image)
        let cached = await store.image(at: url)
        XCTAssertTrue(cached === image)
        XCTAssertEqual(requests, 1)
    }

    func testEvictedSourceReloadsEncryptedDiskCacheWithoutNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SourceChannelCache(directory: directory, maximumMemorySources: 1)
        let first = MediaSource(name: "First", kind: .playlist), second = MediaSource(name: "Second", kind: .playlist)
        let saved = [channel(1)]
        _ = try await cache.channels(for: first) { saved }
        _ = try await cache.channels(for: second) { [self.channel(2)] }
        XCTAssertNil(cache.cached(for: first))
        XCTAssertNotNil(cache.cached(for: second))
        let restored = try await cache.channels(for: first) { XCTFail("Memory eviction must retain the encrypted disk cache"); return [] }
        XCTAssertEqual(restored, saved)
        XCTAssertNil(cache.cached(for: second))
    }

    private func channel(_ id: Int) -> MediaChannel {
        MediaChannel(title: "Movie \(id)", url: URL(string: "https://example.invalid/movie/\(id).m3u8")!)
    }

    func testCarPlayOpensCachedListWithoutWaitingOrPushingAgainAfterRefresh() async throws {
        let request = CarPlayCatalogRequest()
        var finishRefresh: CheckedContinuation<[MediaChannel], Error>?
        var shown: [[MediaChannel]] = []
        var completions = 0
        let saved = [channel(1)], fresh = [channel(2)]
        request.start(load: { cached in
            cached(saved)
            return try await withCheckedThrowingContinuation { finishRefresh = $0 }
        }, show: { shown.append($0) }, failure: { XCTFail("Cached list must remain usable") }, completion: { completions += 1 })
        for _ in 0..<100 where finishRefresh == nil { await Task.yield() }
        XCTAssertEqual(shown, [saved])
        XCTAssertEqual(completions, 1)
        try XCTUnwrap(finishRefresh).resume(returning: fresh)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(shown, [saved], "Refreshing must not reset the selected CarPlay page")
        XCTAssertEqual(completions, 1)
        request.cancel()
        XCTAssertEqual(completions, 1)
    }

    func testDisconnectedCarPlayRejectsLateCacheAndNetworkResults() async throws {
        let request = CarPlayCatalogRequest()
        var cached: (@MainActor ([MediaChannel]) -> Void)?
        var finish: CheckedContinuation<[MediaChannel], Error>?
        var completions = 0
        request.start(load: { callback in
            cached = callback
            return try await withCheckedThrowingContinuation { finish = $0 }
        }, show: { _ in XCTFail("Disconnected screen must not navigate") },
                      failure: { XCTFail("Cancelled requests must stay silent") }, completion: { completions += 1 })
        for _ in 0..<100 where finish == nil { await Task.yield() }
        request.cancel()
        XCTAssertEqual(completions, 1, "Disconnect must release the selection spinner immediately")
        cached?([channel(1)])
        try XCTUnwrap(finish).resume(returning: [channel(2)])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(completions, 1)
    }

    func testCarPlayNavigationReplacementOwnsItsCompletionAndIgnoresOldResults() async throws {
        let request = CarPlayCatalogRequest()
        var oldRefresh: CheckedContinuation<[MediaChannel], Error>?
        var newLoad: CheckedContinuation<[MediaChannel], Error>?
        var shown: [Int] = []
        var completions: [Int] = []
        request.start(load: { cached in
            cached([self.channel(1)])
            return try await withCheckedThrowingContinuation { oldRefresh = $0 }
        }, show: { _ in
            shown.append(1)
            request.start(load: { _ in
                try await withCheckedThrowingContinuation { newLoad = $0 }
            }, show: { _ in shown.append(2) }, failure: { XCTFail("New navigation must succeed") },
                          completion: { completions.append(2) })
        }, failure: { XCTFail("Superseded refresh must stay silent") }, completion: { completions.append(1) })
        for _ in 0..<100 where oldRefresh == nil || newLoad == nil { await Task.yield() }
        XCTAssertEqual(completions, [1], "The old result must not finish the new selection's spinner")
        try XCTUnwrap(oldRefresh).resume(throwing: URLError(.timedOut))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(shown, [1])
        XCTAssertEqual(completions, [1])
        try XCTUnwrap(newLoad).resume(returning: [channel(2)])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(shown, [1, 2])
        XCTAssertEqual(completions, [1, 2])
    }

    func testCancellingHLSPreparationRejectsAnUncooperativeLateResult() async throws {
        let preparation = OfflineDownloadPreparation()
        let id = UUID(), url = channel(1).url
        var finish: CheckedContinuation<AVURLAsset, Never>?
        let pending = Task {
            try await preparation.asset(id: id, url: url) { url in
                await withCheckedContinuation { finish = $0 }
            }
        }
        for _ in 0..<100 where finish == nil { await Task.yield() }
        preparation.cancel(id)
        try XCTUnwrap(finish).resume(returning: AVURLAsset(url: url))
        do { _ = try await pending.value; XCTFail("Cancelled preparation must not start a download") }
        catch is CancellationError { }
    }

    func testDownloadProgressCallbacksAreBoundedAndIndependent() {
        let updates = OfflineProgressUpdates()
        let first = UUID(), second = UUID()
        var accepted = 0
        for n in 0..<1000 {
            if updates.accepts(Double(n) / 1000, id: first, now: Double(n) / 1000) { accepted += 1 }
        }
        XCTAssertEqual(accepted, 4, "A thousand network callbacks must not schedule a thousand UI tasks")
        XCTAssertTrue(updates.accepts(0.5, id: second, now: 0.1))
        XCTAssertFalse(updates.accepts(0.5, id: second, now: 1))
        XCTAssertFalse(updates.accepts(.nan, id: first, now: 2))
        updates.remove(first)
        XCTAssertTrue(updates.accepts(0, id: first, now: 2))
    }

    func testCancelledHLSPreparationDoesNotSurfaceALateNetworkFailure() async throws {
        let preparation = OfflineDownloadPreparation()
        let id = UUID(), url = channel(1).url
        var finish: CheckedContinuation<AVURLAsset, Error>?
        let pending = Task {
            try await preparation.asset(id: id, url: url) { _ in
                try await withCheckedThrowingContinuation { finish = $0 }
            }
        }
        for _ in 0..<100 where finish == nil { await Task.yield() }
        preparation.cancel(id)
        try XCTUnwrap(finish).resume(throwing: URLError(.cancelled))
        do { _ = try await pending.value; XCTFail("Cancelled preparation must finish as cancellation") }
        catch is CancellationError { }
    }

    func testFailedSourceDeletionPreservesListAndCredentials() throws {
        for clearAll in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = SourceLibrary(directory: directory)
            try library.add(name: "Saved", kind: .playlist, secret: SourceSecret(url: channel(1).url),
                            access: ProductAccess(salesEnabled: true, verifiedPro: true))
            let source = try XCTUnwrap(library.sources.first)
            defer {
                try? SourceKeychain.delete(source.id)
                try? FileManager.default.removeItem(at: directory)
            }
            let file = directory.appendingPathComponent("sources.json")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            if clearAll { XCTAssertThrowsError(try library.clear()) }
            else { XCTAssertThrowsError(try library.delete(source)) }
            XCTAssertEqual(library.sources, [source])
            XCTAssertEqual(try SourceKeychain.read(source.id).url, channel(1).url)
        }
    }

    func testIdleRefreshDoesNotInvalidatePhoneOrCarPlayViews() async {
        let model = MirrorModel(viewingAccess: { ProductAccess(salesEnabled: true, verifiedPro: true) }, startsTimer: false)
        for _ in 0..<20 { await Task.yield() }
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        for _ in 0..<20 { model.refresh() }
        XCTAssertEqual(changes, 0)
        subscription.cancel()
    }
}

@MainActor
final class VehiclePlaybackTests: XCTestCase {
    func testCarPlayPreparedVideoAutoplaysAndAnExplicitPauseSurvivesPreparation() async throws {
        let native = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let converted = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let multiAudio = URL(string: "http://127.0.0.1:8769/tracks/options.mkv")!
        let errorObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry,
            object: nil, queue: .main) { notification in
            if let item = notification.object as? AVPlayerItem, let event = item.errorLog()?.events.last {
                print("CarPlay fixture error: \(event.errorDomain) \(event.errorStatusCode) \(event.errorComment ?? "")")
            }
        }
        defer { NotificationCenter.default.removeObserver(errorObserver) }
        for (source, live) in [(native, true), (native, false), (converted, false), (multiAudio, false)] {
            let playback = PlaybackController()
            var preparationFailure: DiagnosticFailure?
            playback.onDiagnostic = { kind, values in
                if kind == .failure { preparationFailure = values.failure }
            }
            playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
            defer { playback.stop() }
            try playback.play(url: source, requiresExternalPlayback: false, live: live, startPaused: true)
            // Preparing a selection must not activate the video receiver.
            XCTAssertFalse(playback.player.allowsExternalPlayback)
            for _ in 0..<600 {
                if playback.player.currentItem?.status == .readyToPlay && playback.player.allowsExternalPlayback { break }
                if playback.state == .failed { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(playback.player.currentItem?.status, .readyToPlay,
                           "\(source.lastPathComponent), state=\(playback.state), failure=\(String(describing: preparationFailure))")
            XCTAssertTrue(playback.player.allowsExternalPlayback, "Preparation must finish without pressing Play")
            XCTAssertFalse(playback.isPlaying, "An explicit pause must survive preparation")
            let item = try XCTUnwrap(playback.player.currentItem)
            let video = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            item.add(video)
            playback.resume()
            var frame: CVPixelBuffer?
            for _ in 0..<200 {
                frame = video.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: nil)
                if playback.isPlaying && frame != nil { break }
                if playback.state == .failed { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(playback.isPlaying, "\(source.lastPathComponent): prepared media must start automatically on resume")
            XCTAssertNotNil(frame, "\(source.lastPathComponent): playing must produce an actual decoded video frame")
            playback.stop()
            XCTAssertNil(playback.player.currentItem)
            XCTAssertFalse(playback.isPlaying)
        }
    }

    func testCarPlayStopCancelsAnUnfinishedVideoPreparation() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let playback = PlaybackController()
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        try playback.play(url: source, requiresExternalPlayback: false, live: false)
        playback.stop()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(playback.player.currentItem)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.state, .idle)
    }

    func testCarPlayVODServerGeneratesARequestedFutureSegment() async throws {
        let playlist = try CarPlayVODPlaylist(duration: 3_441)
        let server = try CarPlayHLSServer(vod: true, playlist: playlist)
        defer { server.stop(); server.removeOutput() }
        let segment = Data(repeating: 0x47, count: 1_880)
        let cachedRequest = expectation(description: "Reading a cached segment advances lookahead once")
        cachedRequest.assertForOverFulfill = true
        server.onSegmentRequested = { index in
            let file = server.directory.appendingPathComponent(playlist.name(for: index))
            if FileManager.default.fileExists(atPath: file.path) { cachedRequest.fulfill(); return }
            do {
                try segment.write(to: file, options: .atomic)
                server.segmentReady(index)
            } catch { XCTFail("Segment generation failed: \(error)") }
        }
        let address: URL = try await withCheckedThrowingContinuation { continuation in
            server.start(host: "127.0.0.1", onReady: { continuation.resume(returning: $0) },
                         onFailure: { continuation.resume(throwing: $0) })
        }
        let (manifest, _) = try await URLSession.shared.data(from: address)
        XCTAssertEqual(manifest, playlist.manifest)
        let lastSegment = playlist.name(for: playlist.segmentCount - 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: server.directory.appendingPathComponent(lastSegment).path))
        let (bytes, response) = try await URLSession.shared.data(from: address.deletingLastPathComponent().appendingPathComponent(lastSegment))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, segment)
        var seekRequest = URLRequest(url: address.deletingLastPathComponent().appendingPathComponent(lastSegment))
        seekRequest.setValue("bytes=188-", forHTTPHeaderField: "Range")
        let (wholeSegment, seekResponse) = try await URLSession.shared.data(for: seekRequest)
        await fulfillment(of: [cachedRequest], timeout: 2)
        XCTAssertEqual((seekResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(wholeSegment, segment, "A VOD seek must retain the segment's reference frames")
        let (_, invalid) = try await URLSession.shared.data(from:
            address.deletingLastPathComponent().appendingPathComponent(playlist.name(for: playlist.segmentCount)))
        XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 404)
    }

    func testCarPlayVODPreparesTheNextSegmentBeforeTheStartupBufferRunsOut() async throws {
        let usesDeviceFixture = ProcessInfo.processInfo.environment["MIRIVO_TEST_VOD_FILE"] == "1"
        let source = usesDeviceFixture
            ? URL.cachesDirectory.appendingPathComponent("mirivo-carplay-prefetch-test.mkv")
            : URL(string: "http://127.0.0.1:8769/tracks/options.mkv")!
        defer { if usesDeviceFixture { try? FileManager.default.removeItem(at: source) } }
        try await assertCarPlayPrefetch(source: source)
    }

    func testCarPlayPrefetchesTheUsersLastSelectedVOD() async throws {
        guard ProcessInfo.processInfo.environment["MIRIVO_TEST_SAVED_VOD"] == "1" else {
            throw XCTSkip("Requires explicit opt-in to test the last selected provider video")
        }
        guard let record = LastPlaybackStore.shared.record, !record.isLive, !record.channel.isAudio else {
            throw XCTSkip("No saved on-demand video")
        }
        try await assertCarPlayPrefetch(source: record.channel.url)
    }

    private func assertCarPlayPrefetch(source: URL) async throws {
        let bridge = CarPlayHLSBridge(source: source, live: false, startPosition: 0)
        defer { bridge.stop() }
        let address: URL = try await withCheckedThrowingContinuation { continuation in
            bridge.onReady = { address in
                bridge.onFailure = { error in
                    let failure = DiagnosticFailure(error)
                    XCTFail("Prefetch failed: \(failure.family.rawValue):\(failure.code)")
                }
                continuation.resume(returning: address)
            }
            bridge.onFailure = { continuation.resume(throwing: $0) }
            bridge.start()
        }
        let playlist = try CarPlayVODPlaylist(duration: bridge.duration)
        for index in 1..<min(playlist.segmentCount, 4) {
            let previous = try XCTUnwrap(playlist.interval(for: index - 1))
            let began = ContinuousClock.now
            let (bytes, response) = try await URLSession.shared.data(from:
                address.deletingLastPathComponent().appendingPathComponent(playlist.name(for: index)))
            let elapsed = began.duration(to: .now)
            print("CarPlay VOD prefetch \(index): \(elapsed)")
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertFalse(bytes.isEmpty)
            XCTAssertEqual(bytes.count % 188, 0, "Only complete transport segments may reach the receiver")
            XCTAssertLessThan(elapsed, .seconds(previous.upperBound - previous.lowerBound),
                              "The next segment must be ready before the current buffer has played")
        }
    }

    func testConvertedCarPlayEpisodeHasAFiniteNativeTimelineAndCanSeek() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        try playback.play(url: source, requiresExternalPlayback: false, title: "VOD seek QA", live: false, presentation: .video)
        for _ in 0..<600 {
            if playback.player.currentItem?.status == .readyToPlay && playback.canSeek { break }
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let item = try XCTUnwrap(playback.player.currentItem)
        XCTAssertEqual(item.status, .readyToPlay)
        XCTAssertTrue(item.duration.seconds.isFinite)
        XCTAssertGreaterThan(item.duration.seconds, 6)
        XCTAssertFalse(item.duration.isIndefinite, "The video receiver must not see an episode as LIVE")
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(output)
        playback.pause()
        playback.seek(to: 6)
        for _ in 0..<100 {
            if abs(playback.player.currentTime().seconds - 6) < 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.player.currentItem === item, "Native seeking must retain the VOD item")
        XCTAssertEqual(playback.player.currentTime().seconds, 6, accuracy: 0.2)
        XCTAssertFalse(playback.isPlaying)
        var frame: CVPixelBuffer?
        var frameTime = CMTime.invalid
        for _ in 0..<100 {
            frame = output.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: &frameTime)
            if frame != nil, frameTime.seconds.isFinite, abs(frameTime.seconds - 6) < 0.2 { break }
            frame = nil
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertNotNil(frame, "Seeking must decode the target video frame")
    }

    func testConvertedCarPlayVideoDecodesAcrossSegmentBoundariesWithoutASecondPlay() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.updateConnectedDisplays(carPlay: true, externalTV: false, supportsCarPlayVideo: true)
        try playback.play(url: source, requiresExternalPlayback: false, live: false)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        var observedItem: AVPlayerItem?
        var decodedSeconds = 0.0
        let deadline = ContinuousClock.now + .seconds(24)
        while ContinuousClock.now < deadline, decodedSeconds < 12.5, playback.state != .failed {
            if let item = playback.player.currentItem {
                if item !== observedItem { item.add(output); observedItem = item }
                var frameTime = CMTime.invalid
                if output.copyPixelBuffer(forItemTime: playback.player.currentTime(), itemTimeForDisplay: &frameTime) != nil,
                   frameTime.isNumeric { decodedSeconds = max(decodedSeconds, frameTime.seconds) }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(decodedSeconds, 12.5, "The third segment must display without a seek or another Play command")
    }

    func testCarPlayStartsPlaybackOnlyAfterWaitingScreenAndSelectionHandlerFinish() async throws {
        let transition = CarPlayPlaybackTransition()
        var presented: ((Bool) -> Void)?
        var events: [String] = []
        transition.start(preparePlayback: { events.append("prepared-paused"); return true }, showWaiting: { completed in
            events.append("waiting")
            presented = completed
        }, playback: { events.append("playback") })
        XCTAssertEqual(events, ["prepared-paused", "waiting"])
        try XCTUnwrap(presented)(true)
        events.append("handler-finished")
        XCTAssertEqual(events, ["prepared-paused", "waiting", "handler-finished"])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(events, ["prepared-paused", "waiting", "handler-finished", "playback"])
    }

    func testCarPlayDoesNotStartStaleFailedOrDisconnectedSelections() async {
        let transition = CarPlayPlaybackTransition()
        var callbacks: [(Bool) -> Void] = []
        var started: [Int] = []
        transition.start(preparePlayback: { true }, showWaiting: { callbacks.append($0) }, playback: { started.append(1) })
        transition.start(preparePlayback: { true }, showWaiting: { callbacks.append($0) }, playback: { started.append(2) })
        callbacks[0](true)
        callbacks[1](false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(started.isEmpty)
        transition.start(preparePlayback: { true }, showWaiting: { callbacks.append($0) }, playback: { started.append(3) })
        callbacks[2](true)
        transition.cancel()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(started.isEmpty)
        transition.start(preparePlayback: { false }, showWaiting: { _ in XCTFail("Failed preparation must not open Now Playing") },
                         playback: { started.append(4) })
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(started.isEmpty)
    }

    func testCarPlayFavoritesPreserveSourcesAndSeparateSeriesNavigationFromPlayback() throws {
        let sourceA = UUID(), sourceB = UUID()
        let episode = MediaChannel(title: "Coast S01-E01", url: URL(string: "https://example.com/series/1.mp4")!)
        let movie = MediaChannel(title: "Movie", url: URL(string: "https://example.com/movie/2.mp4")!)
        let entries = [FavoriteMedia(channel: episode, sourceID: sourceA, wholeSeries: true),
                       FavoriteMedia(channel: episode, sourceID: sourceA),
                       FavoriteMedia(channel: movie, sourceID: sourceB)]
        let template = CPListTemplate(title: "Favorites", sections: [])
        var selected: [FavoriteMedia] = []
        var completed = 0
        CarPlayFavoritesMenu.update(template, entries: entries, sourceNames: [sourceA: "A", sourceB: "B"],
                                    supportsVideo: true, open: { favorite, completion in
            selected.append(favorite); completion(favorite.series == nil)
        }, page: { _ in XCTFail("Selecting content must not change pages") })
        let items = try XCTUnwrap(template.sections.first).items.compactMap { $0 as? CPListItem }
        XCTAssertEqual(items.map(\.text), ["Coast", episode.title, movie.title])
        XCTAssertEqual(items[0].detailText, L10n.tr("Dizi") + " · A")
        XCTAssertEqual(items[1].detailText, L10n.tr("Bölüm") + " · A")
        if #available(iOS 26.4, *) {
            XCTAssertNil(items[0].playbackConfiguration, "A series must open its episode list instead of autoplaying")
            XCTAssertNotNil(items[1].playbackConfiguration)
            XCTAssertNotNil(items[2].playbackConfiguration)
        }
        for item in items { try XCTUnwrap(item.handler)(item) { completed += 1 } }
        XCTAssertEqual(completed, 3)
        XCTAssertEqual(selected.map(\.id), entries.map(\.id))
        XCTAssertEqual(selected.map(\.sourceID), [sourceA, sourceA, sourceB])
    }

    func testCarPlayFavoritePaginationHandlesRemovalAndEmptyLibrary() throws {
        let entries = (0..<95).map { index in
            FavoriteMedia(channel: MediaChannel(title: "Movie \(index)", url: URL(string: "https://example.com/movie/\(index).mp4")!), sourceID: nil)
        }
        let template = CPListTemplate(title: "Favorites", sections: [])
        var page = 0
        let update: ([FavoriteMedia], Int) -> Int = { entries, offset in
            CarPlayFavoritesMenu.update(template, entries: entries, offset: offset, supportsVideo: false,
                open: { _, _ in XCTFail("Pagination must not start playback") }, page: { page = $0 })
        }
        XCTAssertEqual(update(entries, 0), 0)
        let next = try XCTUnwrap(template.sections.first?.items.last as? CPListItem)
        XCTAssertEqual(next.text, L10n.tr("Sonraki"))
        var completed = false
        try XCTUnwrap(next.handler)(next) { completed = true }
        XCTAssertTrue(completed)
        XCTAssertGreaterThan(page, 0)
        XCTAssertEqual(update(entries, page), page)
        let previous = try XCTUnwrap(template.sections.first?.items.first as? CPListItem)
        XCTAssertEqual(previous.text, L10n.tr("Önceki sayfa"))
        XCTAssertLessThanOrEqual(template.itemCount, CPListTemplate.maximumItemCount)
        XCTAssertEqual(update([entries[0]], page), 0, "Removing favorites must not leave an empty later page")
        XCTAssertEqual(template.itemCount, 1)
        XCTAssertEqual(update([], page), 0)
        XCTAssertEqual(template.itemCount, 0)
        XCTAssertFalse(template.emptyViewSubtitleVariants.isEmpty)
    }

    func testCarPlayPreparesSelectionsBeforePublishingVideoAndCanSelectAgain() throws {
        let channels = [
            MediaChannel(title: "Live", url: URL(string: "https://example.com/live/1.m3u8")!),
            MediaChannel(title: "Movie", url: URL(string: "https://example.com/movie/2.mp4")!),
            MediaChannel(title: "Coast S01-E01", url: URL(string: "https://example.com/series/3.mp4")!),
            MediaChannel(title: "Radio", url: URL(string: "https://example.com/radio/4.mp3")!)
        ]
        let entries = channels.map { FavoriteMedia(channel: $0, sourceID: nil) }
        let template = CPListTemplate(title: "Favorites", sections: [])
        for supportsVideo in [true, false] {
            CarPlayFavoritesMenu.update(template, entries: entries, supportsVideo: supportsVideo,
                open: { _, completed in completed(true) }, page: { _ in })
            let items = try XCTUnwrap(template.sections.first).items.compactMap { $0 as? CPListItem }
            XCTAssertEqual(items.count, 4)
            if #available(iOS 26.4, *) {
                XCTAssertTrue(items.allSatisfy { $0.playbackConfiguration?.preferredPresentation == .audio },
                              "Selection must reach the app before requesting a video route")
                let expected: [CPPlaybackConfiguration.Presentation] = supportsVideo
                    ? [.video, .video, .video, .audio] : [.audio, .audio, .audio, .audio]
                for (item, expectedPresentation) in zip(items, expected) {
                    var completed = false
                    try XCTUnwrap(item.handler)(item) {
                        completed = true
                        XCTAssertEqual(item.playbackConfiguration?.preferredPresentation, expectedPresentation)
                    }
                    XCTAssertTrue(completed)
                }
                CarPlayPlaybackTransition.resetSelections(in: template)
                XCTAssertTrue(items.allSatisfy { $0.playbackConfiguration?.preferredPresentation == .audio },
                              "Returning to a list must allow another selection even after playback stopped")
                for (channel, expectedPresentation) in zip(channels, expected) {
                    let configuration = CarPlayPlaybackTransition.configuration(for: channel, supportsVideo: supportsVideo)
                    XCTAssertEqual(configuration.preferredPresentation, expectedPresentation)
                    XCTAssertEqual(configuration.playbackAction, .play)
                }
            }
        }
    }

    func testFailedCarPlayPreparationKeepsSelectionRetryable() throws {
        let favorite = FavoriteMedia(channel: MediaChannel(title: "Movie", url: URL(string: "https://example.com/movie/1.mp4")!), sourceID: nil)
        let template = CPListTemplate(title: "Favorites", sections: [])
        var attempts = 0, completed = 0
        CarPlayFavoritesMenu.update(template, entries: [favorite], supportsVideo: true,
            open: { _, done in attempts += 1; done(false) }, page: { _ in })
        let item = try XCTUnwrap(template.sections.first?.items.first as? CPListItem)
        for _ in 0..<2 {
            try XCTUnwrap(item.handler)(item) { completed += 1 }
            if #available(iOS 26.4, *) { XCTAssertEqual(item.playbackConfiguration?.preferredPresentation, .audio) }
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(completed, 2)
    }

    func testOfflineFavoriteResolvesOriginalChannelWithinItsSource() throws {
        let source = UUID()
        let original = MediaChannel(title: "Coast S01-E02", url: URL(string: "https://example.com/series/u/p/2.mp4")!)
        let local = MediaChannel(title: original.title, url: URL(fileURLWithPath: "/tmp/offline.mp4"))
        let download = OfflineDownload(id: UUID(), title: original.title, group: "", sourceID: source,
            assetKey: OfflineDownloadStore.assetKey(for: original.url), state: .finished, progress: 1,
            packagePath: local.url.path)
        XCTAssertTrue(OfflineDownload.originalChannels(for: [download], in: [original], sourceID: UUID()).isEmpty)
        XCTAssertTrue(OfflineDownload.originalChannels(for: [download], in: [local], sourceID: source).isEmpty)
        let resolved = try XCTUnwrap(OfflineDownload.originalChannels(for: [download], in: [local, original], sourceID: source)[download.id])
        let store = MediaFavorites(account: "offline-favorite-\(UUID())")
        defer { try? store.clear() }
        try store.toggle(resolved, sourceID: source)
        XCTAssertTrue(store.contains(original, sourceID: source))
        XCTAssertEqual(store.entries.first?.channel.url, original.url)
        XCTAssertFalse(store.contains(local, sourceID: nil))
    }

    func testPhoneHandoffKeepsDecoderPositionAndRestoresCaptureProtection() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.frame = scene.screen.bounds
        window.isHidden = false
        let playback = PlaybackController()
        defer { playback.stop(); window.isHidden = true; window.rootViewController = nil }
        playback.externalDisplayConnected = true
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        try playback.play(url: url, requiresExternalPlayback: false, live: false, useCompatibility: true)
        let engine = try XCTUnwrap(playback.compatibility)
        let phone = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let car = CompatibilityVideoHost(frame: CGRect(x: 0, y: 200, width: 390, height: 180))
        window.rootViewController?.view.addSubview(phone)
        window.rootViewController?.view.addSubview(car)
        phone.configure(engine: engine, role: .inline, displayMode: .normal)
        car.configure(engine: engine, role: .external, displayMode: .normal)
        for _ in 0..<100 {
            if engine.videoView.pictureInPictureLayer?.isReadyForDisplay == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(engine.videoView.superview === car)
        let layer = try XCTUnwrap(engine.videoView.pictureInPictureLayer)
        XCTAssertFalse(layer.preventsCapture, "Authorized external rendering must remain visible to CarPlay")
        XCTAssertTrue(layer.isReadyForDisplay, "Check actual decoded output, not only player state")
        if playback.isPlaying { playback.togglePlayPause() }
        try await Task.sleep(for: .milliseconds(150))
        let id = playback.playbackID
        let time = playback.currentTime
        playback.setPlaysOnPhone(true)
        XCTAssertTrue(engine.videoView.superview === phone)
        XCTAssertTrue(layer.preventsCapture)
        XCTAssertFalse(playback.hasRemoteVideoOutput)
        XCTAssertTrue(playback.compatibility === engine)
        XCTAssertEqual(playback.playbackID, id)
        XCTAssertEqual(playback.currentTime, time)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentTime, time, accuracy: 0.3)
        playback.setPlaysOnPhone(false)
        XCTAssertTrue(engine.videoView.superview === car)
        XCTAssertFalse(layer.preventsCapture)
        XCTAssertEqual(playback.playbackID, id)
    }

    func testNativeVideoDoesNotCompeteWithOwnedExternalWindow() throws {
        let playback = PlaybackController()
        defer { playback.stop() }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        playback.externalDisplayConnected = true
        try playback.play(url: url, requiresExternalPlayback: false, live: false)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
        XCTAssertFalse(playback.player.usesExternalPlaybackWhileExternalScreenIsActive)
        let item = playback.player.currentItem
        playback.setPlaysOnPhone(true)
        XCTAssertTrue(playback.player.currentItem === item)
        XCTAssertFalse(playback.hasRemoteVideoOutput)
        playback.setPlaysOnPhone(false)
        XCTAssertTrue(playback.hasRemoteVideoOutput)
        playback.externalDisplayConnected = false
        XCTAssertTrue(playback.player.allowsExternalPlayback)
    }

    func testFavoritesPersistSeparatelyBySourceAndEpisodeAndClearCredentials() throws {
        let account = "vehicle-favorites-\(UUID())"
        let store = MediaFavorites(account: account)
        defer { try? store.clear() }
        let first = MediaChannel(title: "Series S01E01", url: URL(string: "https://example.com/series/u/p/1.mp4")!)
        let second = MediaChannel(title: "Series S01E02", url: URL(string: "https://example.com/series/u/p/2.mp4")!)
        let a = UUID(), b = UUID()
        try store.toggle(first, sourceID: a)
        try store.toggle(second, sourceID: a)
        try store.toggle(first, sourceID: b)
        let restored = MediaFavorites(account: account)
        XCTAssertEqual(restored.entries.count, 3)
        XCTAssertTrue(restored.contains(second, sourceID: a))
        try restored.toggle(first, sourceID: a)
        XCTAssertFalse(restored.contains(first, sourceID: a))
        XCTAssertTrue(restored.contains(first, sourceID: b))
        try restored.clear(sourceID: a)
        XCTAssertEqual(MediaFavorites(account: account).entries.count, 1)
        try restored.clear()
        XCTAssertTrue(MediaFavorites(account: account).entries.isEmpty)
    }

    func testWholeSeriesFavoritesStayDistinctFromEpisodesAndFollowNewSeasons() throws {
        let account = "series-favorites-\(UUID())"
        let store = MediaFavorites(account: account)
        defer { try? store.clear() }
        let source = UUID()
        let first = MediaChannel(title: "Coast S01-E01", group: "Drama", url: URL(string: "https://example.com/series/1.mp4")!)
        let second = MediaChannel(title: "Coast S02-E01", group: "Drama", url: URL(string: "https://example.com/series/2.mp4")!)
        let otherGroup = MediaChannel(title: first.title, group: "Other", url: first.url)
        let series = FavoriteMedia(channel: first, sourceID: source, wholeSeries: true)
        try store.toggle(series)
        try store.toggle(first, sourceID: source)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.contains(FavoriteMedia(channel: second, sourceID: source, wholeSeries: true)))
        XCTAssertFalse(store.contains(FavoriteMedia(channel: first, sourceID: UUID(), wholeSeries: true)))
        XCTAssertFalse(store.contains(FavoriteMedia(channel: otherGroup, sourceID: source, wholeSeries: true)))

        let restored = MediaFavorites(account: account)
        let savedSeries = try XCTUnwrap(restored.entries.first { $0.series != nil })
        XCTAssertEqual(savedSeries.title, "Coast")
        let current = try XCTUnwrap(savedSeries.resolveSeries(in: [otherGroup, second, first]))
        XCTAssertEqual(current.seasons.map(\.number), [1, 2])
        XCTAssertEqual(current.channels, [first, second])
        // A changed first episode URL must not create a second series favorite.
        let replacement = MediaChannel(title: first.title, group: first.group, url: URL(string: "https://example.com/series/replaced.mp4")!)
        try restored.toggle(FavoriteMedia(channel: replacement, sourceID: source, wholeSeries: true))
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertTrue(restored.contains(first, sourceID: source), "Removing the series must retain the separately saved episode")
        try restored.clear(sourceID: source)
        XCTAssertTrue(MediaFavorites(account: account).entries.isEmpty)
    }

    func testPlaybackAndContinuationRecognizeSeriesAndEpisodeFavoritesIndependently() throws {
        let account = "favorite-scopes-\(UUID())"
        let store = MediaFavorites(account: account)
        defer { try? store.clear() }
        let source = UUID()
        let first = MediaChannel(title: "Akil Oyunlari S01-E01", group: "DIZI: Exxen", url: URL(string: "https://example.com/series/1.mp4")!)
        let next = MediaChannel(title: "Akil Oyunlari S01-E03", group: first.group, url: URL(string: "https://example.com/series/3.mp4")!)
        let cafe = MediaChannel(title: "Adim Basi Cafe S01-E01", group: first.group, url: URL(string: "https://example.com/series/4.mp4")!)
        let series = try XCTUnwrap(store.selection(for: first, sourceID: source).series)
        try store.toggle(series)
        try store.toggle(cafe, sourceID: source)

        let restored = MediaFavorites(account: account)
        for channel in [first, next] {
            let state = restored.selection(for: channel, sourceID: source)
            XCTAssertTrue(state.seriesSelected)
            XCTAssertFalse(state.itemSelected, "A saved series must leave unsaved episode hearts empty")
        }
        let cafeState = restored.selection(for: cafe, sourceID: source)
        XCTAssertTrue(cafeState.itemSelected, "An explicitly saved episode must also light its continuation heart")
        XCTAssertFalse(cafeState.seriesSelected)
        XCTAssertFalse(restored.selection(for: first, sourceID: UUID()).itemSelected)
        let unrelated = MediaChannel(title: "Another Show S01-E01", group: first.group, url: URL(string: "https://example.com/series/5.mp4")!)
        XCTAssertFalse(restored.selection(for: unrelated, sourceID: source).itemSelected)

        try restored.toggle(first, sourceID: source)
        XCTAssertTrue(restored.selection(for: first, sourceID: source).itemSelected)
        XCTAssertTrue(restored.selection(for: first, sourceID: source).seriesSelected)
        XCTAssertFalse(restored.selection(for: next, sourceID: source).itemSelected)
        try restored.toggle(first, sourceID: source)
        XCTAssertFalse(restored.selection(for: first, sourceID: source).itemSelected)
        XCTAssertTrue(restored.selection(for: first, sourceID: source).seriesSelected)
        try restored.toggle(first, sourceID: source)
        try restored.toggle(series)
        XCTAssertTrue(restored.selection(for: first, sourceID: source).itemSelected)
        XCTAssertFalse(restored.selection(for: next, sourceID: source).itemSelected)
        try restored.toggle(first, sourceID: source)
        XCTAssertFalse(restored.selection(for: first, sourceID: source).itemSelected)
        XCTAssertEqual(restored.entries.map(\.title), [cafe.title], "Scope changes must preserve unrelated favorites")
        try restored.clear()
    }

    func testLegacyFavoriteDecodesAsEpisodeWithoutChangingIdentity() throws {
        let channel = MediaChannel(title: "Coast S01-E02", url: URL(string: "https://example.com/series/2.mp4")!)
        let source = UUID()
        let record = LastPlaybackRecord(channel: channel, sourceID: source, position: 0, duration: 0, isLive: false)
        // The old storage format had only the record field.
        let legacy = try JSONEncoder().encode(["record": record])
        let decoded = try JSONDecoder().decode(FavoriteMedia.self, from: legacy)
        XCTAssertNil(decoded.series)
        XCTAssertEqual(decoded.channel, channel)
        XCTAssertEqual(decoded.id, FavoriteMedia.id(channel, sourceID: source))
        XCTAssertNotEqual(decoded.id, FavoriteMedia(channel: channel, sourceID: source, wholeSeries: true).id)
    }

    func testFavoriteFallbackDoesNotDuplicateEpisodesOrMixSources() throws {
        let first = MediaChannel(title: "Coast S01-E01", url: URL(string: "https://example.com/series/1.mp4")!)
        let second = MediaChannel(title: "Coast S01-E02", url: URL(string: "https://example.com/series/2.mp4")!)
        let favorite = FavoriteMedia(channel: first, sourceID: nil, wholeSeries: true)
        let local = favorite.fallbackCatalog(currentChannels: [first, second], sourceID: nil)
        XCTAssertEqual(favorite.resolveSeries(in: local)?.channels, [first, second])
        let otherSource = favorite.fallbackCatalog(currentChannels: [second], sourceID: UUID())
        XCTAssertEqual(favorite.resolveSeries(in: otherSource)?.channels, [first])
    }

    func testVehicleAndPhoneLayouts() async throws {
        let model = MirrorModel(viewingAccess: { ProductAccess(salesEnabled: false, verifiedPro: false) }, startsTimer: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let displayID = UUID()
        let previousLanguage = SharedPreferences.defaults.string(forKey: "language")
        SharedPreferences.defaults.set("tr", forKey: "language")
        defer {
            model.stopPlayback(); model.externalScreenDisconnected(displayID)
            window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible()
            SharedPreferences.defaults.set(previousLanguage, forKey: "language")
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let first = MediaChannel(title: "Kıyı Hikâyeleri S01-E01", url: url)
        let second = MediaChannel(title: "Kıyı Hikâyeleri S01-E02", url: url.appending(queryItems: [URLQueryItem(name: "episode", value: "2")]))
        model.externalScreenConnected(displayID, role: .carPlay, size: CGSize(width: 1000, height: 420))
        XCTAssertTrue(model.playMedia(first, queue: [first, second]))
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 420)
        let external = UIHostingController(rootView: ExternalDisplayPlayerView(model: model).preferredColorScheme(.dark))
        window.rootViewController = external; window.makeKeyAndVisible()
        for _ in 0..<100 {
            if model.playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(model.playback.isPlaying)
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(400))
        capture(external.view, "vehicle-external-player")
        window.frame = scene.screen.bounds
        let phone = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) }.preferredColorScheme(.dark))
        window.rootViewController = phone
        try await Task.sleep(for: .milliseconds(600))
        capture(phone.view, "vehicle-remote-panel")
        model.playerVisibilityChanged(false)
        let mini = UIHostingController(rootView: VStack { Spacer(); NowPlayingBar(model: model) {} }
            .background(MirrorStyle.background).preferredColorScheme(.dark))
        window.rootViewController = mini
        try await Task.sleep(for: .milliseconds(600))
        capture(mini.view, "vehicle-mini-player")
        let connection = UIHostingController(rootView: TVConnectionView(model: model))
        window.rootViewController = connection
        try await Task.sleep(for: .milliseconds(600))
        capture(connection.view, "vehicle-connections")
    }

    private func capture(_ view: UIView, _ name: String) {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? image.pngData()?.write(to: file)
        print("VEHICLE_LAYOUT_CAPTURE: \(file.path)")
    }

    func testLiveFragmentStreamDecodesAtTheExternalSurface() async throws {
        guard let value = ProcessInfo.processInfo.environment["MIRIVO_TEST_STREAM_URL"], let url = URL(string: value) else {
            throw XCTSkip("Run with the live screen encoder fixture")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.frame = scene.screen.bounds
        window.isHidden = false
        let playback = PlaybackController()
        defer { playback.stop(); window.isHidden = true; window.rootViewController = nil }
        playback.externalDisplayConnected = true
        let start = Date()
        try playback.play(url: url, requiresExternalPlayback: false, useCompatibility: true, lowLatency: true)
        let engine = try XCTUnwrap(playback.compatibility)
        let car = CompatibilityVideoHost(frame: CGRect(x: 0, y: 100, width: 390, height: 220))
        window.rootViewController?.view.addSubview(car)
        car.configure(engine: engine, role: .external, displayMode: .normal)
        for _ in 0..<120 {
            if engine.videoView.pictureInPictureLayer?.isReadyForDisplay == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(engine.videoView.pictureInPictureLayer?.isReadyForDisplay == true)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.isLive)
        XCTAssertFalse(playback.canSeek)
        print("VEHICLE_STREAM_FIRST_FRAME_SECONDS: \(Date().timeIntervalSince(start))")
        let firstTime = playback.currentTime
        try await Task.sleep(for: .seconds(20))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.currentTime, firstTime + 18)
        // VLC reports time relative to the first received fragment. Read the
        // fixture's clock from actual decoded pixels to measure its latency.
        let pausedAt = Date().timeIntervalSince1970
        playback.togglePlayPause()
        let renderer = try XCTUnwrap(engine.videoView.pictureInPictureLayer?.sampleBufferRenderer)
        var pixel: CVPixelBuffer?
        for _ in 0..<20 {
            pixel = renderer.displayedPixelBuffer()
            if pixel != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let frame = try XCTUnwrap(pixel)
        let width = CVPixelBufferGetWidth(frame), height = CVPixelBufferGetHeight(frame)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(CIImage(cvPixelBuffer: frame), toBitmap: &rgba,
            rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var ticks = 0
        for bit in 0..<24 {
            let x = Int((90.0 + Double(bit) * 20) * Double(width) / 640)
            if rgba[(height / 2 * width + x) * 4 + 1] > 128 { ticks |= 1 << bit }
        }
        let epoch = try XCTUnwrap(ProcessInfo.processInfo.environment["MIRIVO_TEST_STREAM_STARTED"].flatMap(Double.init))
        let delay = pausedAt - epoch - Double(ticks) / 10
        print("VEHICLE_STREAM_DECODED_FRAME_DELAY_SECONDS: \(delay)")
        XCTAssertGreaterThan(delay, -0.3)
        XCTAssertLessThan(delay, 2, "The displayed picture must stay near the live edge")
    }
}
