import XCTest
import SwiftUI
import AVFoundation
import CoreImage
import CarPlay
@testable import CarMirror

@MainActor
final class VehiclePlaybackTests: XCTestCase {
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
            selected.append(favorite); completion()
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
        let url = URL(string: "http://127.0.0.1:18779/Kiyi-Hikayeleri-S01-E01.mp4")!
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
