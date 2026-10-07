import XCTest
import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import Security
@preconcurrency import VLCKit
@testable import CarMirror

@MainActor
final class CarPlayAudioTests: XCTestCase {
    func testContinueWatchingGroupsSeriesKeepsMoviesAndCleansCompletedAndSources() throws {
        let account = "continue-test-\(UUID())"
        let store = LastPlaybackStore(account: account)
        defer { try? store.clear() }
        let firstSource = UUID(), secondSource = UUID()
        func entry(_ name: String, _ path: String, source: UUID? = nil, position: Double = 180, live: Bool = false) -> LastPlaybackRecord {
            LastPlaybackRecord(channel: MediaChannel(title: name, url: URL(string: "https://example.com/\(path)")!),
                               sourceID: source ?? firstSource, position: position, duration: 3600, isLive: live)
        }
        let episode1 = entry("Kıyı Hikâyeleri S01-E01", "ep1.mp4")
        let episode2 = entry("Kıyı Hikâyeleri S01-E02", "ep2.mp4")
        let film = entry("Uzun Yol", "film.mp4")
        try store.save(episode1); try store.save(film); try store.save(episode2)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.title, episode2.title)
        XCTAssertEqual(store.entries.first?.resumePosition, 180)
        XCTAssertEqual(episode1.id, episode2.id)
        XCTAssertEqual(entry("Kıyı Hikâyeleri 1x03", "ep3.mp4").id, episode2.id)
        XCTAssertNotEqual(entry("S01-E01", "unrelated.mp4").id, episode2.id)
        let otherProvider = entry(episode2.title, "other.mp4", source: secondSource)
        try store.save(otherProvider)
        XCTAssertEqual(store.entries.count, 3, "Different providers must not merge their content")
        try store.save(entry(episode1.title, "ep1.mp4", position: 3599))
        XCTAssertTrue(store.entries.contains { $0.url == episode2.url }, "Finishing an older episode must keep the newer continuation")
        try store.save(entry("Kıyı Hikâyeleri S01-E03", "ep3.mp4", position: 5))
        try store.save(entry("Brief preview", "preview.mp4", position: 5))
        try store.save(entry("Live", "channel.m3u8", live: true))
        XCTAssertEqual(store.entries.count, 3, "Brief previews and live channels must not fill the collection")
        try store.save(entry(episode2.title, "ep2.mp4", position: 3599))
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(LastPlaybackStore(account: account).entries, store.entries)
        try store.clear(sourceID: firstSource)
        XCTAssertEqual(store.entries.map(\.sourceID), [secondSource])
        try store.remove(id: otherProvider.id)
        XCTAssertTrue(LastPlaybackStore(account: account).entries.isEmpty)
        XCTAssertNil(LastPlaybackStore(account: account).record)
    }

    func testContinueWatchingIsBoundedAndUpdatesWithoutDuplicates() throws {
        let store = LastPlaybackStore(account: "continue-limit-\(UUID())")
        defer { try? store.clear() }
        var saved: [LastPlaybackRecord] = []
        for index in 0..<35 {
            let entry = LastPlaybackRecord(channel: MediaChannel(title: "Film \(index)", url: URL(string: "https://example.com/\(index).mp4")!),
                                           sourceID: nil, position: 300, duration: 7200, isLive: false)
            saved.append(entry); try store.save(entry)
        }
        XCTAssertEqual(store.entries.count, LastPlaybackStore.maximumEntries)
        XCTAssertEqual(store.entries.first?.id, saved.last?.id)
        XCTAssertFalse(store.entries.contains { $0.id == saved[0].id })
        let updated = LastPlaybackRecord(channel: saved[10].channel, sourceID: nil, position: 600, duration: 7200, isLive: false)
        try store.save(updated)
        XCTAssertEqual(store.entries.count, 30)
        XCTAssertEqual(store.entries.first?.resumePosition, 600)
        XCTAssertEqual(store.entries.filter { $0.id == updated.id }.count, 1)
        try store.remove(id: updated.id)
        XCTAssertEqual(store.entries.count, 29)
    }

    func testContinueWatchingMigratesThePreviousSingleKeychainRecord() throws {
        let account = "continue-migration-\(UUID())"
        let old = LastPlaybackRecord(channel: MediaChannel(title: "Saved film", url: URL(string: "https://example.com/saved.mp4")!),
                                     sourceID: nil, position: 420, duration: 7200, isLive: false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "updatedAt")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "com.alperbicer.carmirror.last-playback",
                                  kSecAttrAccount as String: account,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: try JSONSerialization.data(withJSONObject: json)]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        let migrated = LastPlaybackStore(account: account)
        defer { try? migrated.clear() }
        XCTAssertEqual(migrated.record?.resumePosition, 420)
        XCTAssertEqual(migrated.entries.map(\.id), [old.id])
        let second = LastPlaybackRecord(channel: MediaChannel(title: "Second film", url: URL(string: "https://example.com/second.mp4")!),
                                        sourceID: nil, position: 300, duration: 7200, isLive: false)
        try migrated.save(second)
        XCTAssertEqual(LastPlaybackStore(account: account).entries.map(\.id), [second.id, old.id])
    }

    func testRemovingActiveContinuationDoesNotRecreateItAtTheNextCheckpoint() async throws {
        let model = MirrorModel.shared
        let library = SourceLibrary.shared
        try library.add(name: "Continue QA", kind: .stream,
                        secret: SourceSecret(url: URL(string: "http://127.0.0.1:8769/tracks/options.mp4")!),
                        access: ProductAccess(salesEnabled: false, verifiedPro: false))
        let source = try XCTUnwrap(library.sources.last)
        defer { model.stopPlayback(); try? library.delete(source) }
        let channels = try await library.channels(for: source)
        let channel = try XCTUnwrap(channels.first)
        XCTAssertTrue(model.playMedia(channel, sourceID: source.id, startAt: 35))
        for _ in 0..<150 {
            if model.playback.isPlaying && model.playback.currentTime >= 35 && !LastPlaybackStore.shared.entries.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        model.refresh()
        let entry = try XCTUnwrap(LastPlaybackStore.shared.entries.first)
        try model.removeContinuation(entry.id)
        model.refresh(); model.stopPlayback()
        XCTAssertFalse(LastPlaybackStore.shared.entries.contains { $0.id == entry.id })
        XCTAssertFalse(LastPlaybackStore().entries.contains { $0.id == entry.id })
    }

    func testLastPlaybackPersistsSecurelyAndHandlesLiveFinishedAndLocalMedia() throws {
        let account = "resume-test-\(UUID())"
        let store = LastPlaybackStore(account: account)
        defer { try? store.clear() }
        let channel = MediaChannel(title: "Episode", group: "Series", url: URL(string: "https://example.com/episode.mp4?token=fixture")!)
        let sourceID = UUID()
        let saved = LastPlaybackRecord(channel: channel, sourceID: sourceID, position: 123, duration: 900, isLive: false)
        try store.save(saved)
        let reopened = LastPlaybackStore(account: account)
        XCTAssertEqual(reopened.record, saved)
        XCTAssertEqual(reopened.record?.channel, channel)
        XCTAssertEqual(reopened.record?.resumePosition, 123)
        try reopened.clear(sourceID: UUID())
        XCTAssertEqual(reopened.record, saved)
        try reopened.clear(sourceID: sourceID)
        XCTAssertNil(LastPlaybackStore(account: account).record)
        XCTAssertEqual(LastPlaybackRecord(channel: channel, sourceID: nil, position: 123, duration: 900, isLive: true).resumePosition, 0)
        XCTAssertEqual(LastPlaybackRecord(channel: channel, sourceID: nil, position: 899, duration: 900, isLive: false).resumePosition, 0)
        XCTAssertThrowsError(try store.save(LastPlaybackRecord(channel: MediaChannel(title: "Temporary", url: URL(fileURLWithPath: "/tmp/video.mp4")), sourceID: nil, position: 1, duration: 10, isLive: false)))
    }

    func testLastPlaybackRestoresPositionAndSourceDeletionClearsIt() async throws {
        let library = SourceLibrary.shared
        let model = MirrorModel.shared
        try library.add(name: "Resume QA", kind: .stream,
                        secret: SourceSecret(url: URL(string: "http://127.0.0.1:8769/tracks/options.mp4")!),
                        access: ProductAccess(salesEnabled: false, verifiedPro: false))
        let source = try XCTUnwrap(library.sources.last)
        defer { model.stopPlayback(); try? library.delete(source); try? LastPlaybackStore.shared.clear() }
        let channels = try await library.channels(for: source)
        let channel = try XCTUnwrap(channels.first)
        XCTAssertTrue(model.playMedia(channel, sourceID: source.id, startAt: 12))
        for _ in 0..<200 {
            if model.playback.isPlaying && model.playback.currentTime >= 12 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        model.stopPlayback()
        let saved = try XCTUnwrap(LastPlaybackStore().record)
        XCTAssertEqual(saved.sourceID, source.id)
        XCTAssertGreaterThanOrEqual(saved.resumePosition, 12)
        XCTAssertTrue(model.resumeLastPlayback())
        for _ in 0..<200 {
            if model.playback.isPlaying && model.playback.currentTime >= saved.resumePosition { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertGreaterThanOrEqual(model.playback.currentTime, saved.resumePosition)
        model.stopPlayback()
        try library.delete(source)
        XCTAssertNil(LastPlaybackStore.shared.record)
        XCTAssertNil(LastPlaybackStore().record)
    }

    func testNativeAudioAndSubtitleSelectionUsesRealMediaTracks() async throws {
        try await checkMediaTrackSelection(compatibility: false)
    }

    func testCompatibilityAudioAndSubtitleSelectionUsesRealMediaTracks() async throws {
        try await checkMediaTrackSelection(compatibility: true)
    }

    private func checkMediaTrackSelection(compatibility: Bool) async throws {
        let playback = PlaybackController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIHostingController(rootView: MediaVideoView(playback: playback))
        window.makeKeyAndVisible()
        defer { playback.stop(); window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let url = URL(string: "http://127.0.0.1:8769/tracks/options.\(compatibility ? "mkv" : "mp4")")!
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "Tracks QA", live: false, useCompatibility: compatibility)
        for _ in 0..<300 {
            if playback.isPlaying && playback.audioTracks.count == 2 && playback.subtitleTracks.count == 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying, "Playback: \(playback.state), VLC: \(String(describing: playback.compatibility?.mediaPlayer.state))")
        XCTAssertEqual(playback.audioTracks.count, 2)
        XCTAssertEqual(playback.subtitleTracks.count, 2)
        guard playback.audioTracks.count == 2, playback.subtitleTracks.count == 2 else { return }
        let item = playback.player.currentItem
        let engine = playback.compatibility
        let audio = playback.audioTracks[1].id
        let subtitle = playback.subtitleTracks[0].id
        playback.selectAudioTrack(audio)
        playback.selectSubtitleTrack(subtitle)
        for _ in 0..<100 {
            if playback.audioTracks.first(where: { $0.id == audio })?.isSelected == true &&
                playback.subtitleTracks.first(where: { $0.id == subtitle })?.isSelected == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.audioTracks.first(where: { $0.id == audio })?.isSelected, true)
        XCTAssertEqual(playback.subtitleTracks.first(where: { $0.id == subtitle })?.isSelected, true)
        if let engine {
            XCTAssertTrue(engine.mediaPlayer.audioTracks[1].isSelected)
            XCTAssertTrue(engine.mediaPlayer.textTracks[0].isSelected)
        } else if let item {
            let loadedAudio = try await item.asset.loadMediaSelectionGroup(for: .audible)
            let group = try XCTUnwrap(loadedAudio)
            XCTAssertEqual(item.currentMediaSelection.selectedMediaOption(in: group), group.options[1])
            let loadedSubtitles = try await item.asset.loadMediaSelectionGroup(for: .legible)
            let captions = try XCTUnwrap(loadedSubtitles)
            let ordinary = captions.options.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
            XCTAssertEqual(item.currentMediaSelection.selectedMediaOption(in: captions), ordinary[0])
        }
        playback.selectSubtitleTrack(nil)
        for _ in 0..<100 {
            if !playback.subtitleTracks.contains(where: \.isSelected) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(playback.subtitleTracks.contains(where: \.isSelected))
        let position = playback.currentTime
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertGreaterThan(playback.currentTime, position + 0.2, "Track switching must keep video moving")
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.player.currentItem === item)
        XCTAssertTrue(playback.compatibility === engine)
        playback.stop()
        XCTAssertFalse(playback.hasMediaChoices)
    }

    func testImportedPlaylistSurvivesOriginalRemovalAndCleansUpOnReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("file-source-\(UUID())")
        let library = SourceLibrary(directory: directory) { _ in nil }
        defer { try? library.clear(); try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("selected.m3u8")
        let data = Data("#EXTM3U\n#EXTINF:-1 group-title=\"Film\",First\nhttps://example.com/first.mp4\n".utf8)
        try data.write(to: original)
        let access = ProductAccess(salesEnabled: false, verifiedPro: false)
        try library.importPlaylist(original, name: "File source", access: access)
        let source = try XCTUnwrap(library.sources.first)
        XCTAssertEqual(source.kind, .playlistFile)
        let imported = try SourceKeychain.read(source.id).url
        XCTAssertNotEqual(imported, original)
        XCTAssertEqual(try Data(contentsOf: original), data)
        try FileManager.default.removeItem(at: original)
        let reopened = SourceLibrary(directory: directory) { _ in nil }
        let first = try await reopened.channels(for: source)
        XCTAssertEqual(first.first?.title, "First")
        XCTAssertEqual(first.first?.group, "Film")
        try Data("#EXTM3U\nhttps://example.com/second.mp4\n".utf8).write(to: original)
        try library.importPlaylist(original, name: "Replacement", replacing: source, access: access)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
        let replacement = try XCTUnwrap(library.sources.first)
        XCTAssertEqual(replacement.id, source.id)
        let second = try await library.channels(for: replacement)
        XCTAssertEqual(second.first?.url.lastPathComponent, "second.mp4")
        let replacementFile = try SourceKeychain.read(source.id).url
        try library.update(replacement, name: "Direct", kind: .stream, secret: SourceSecret(url: URL(string: "https://example.com/live.mp4")!))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Never delete a user's selected original")
    }

    func testFileSourceRejectsUnsafeOrInvalidFilesAndHonorsFreeSourceLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-file-source-\(UUID())")
        let library = SourceLibrary(directory: directory) { _ in nil }
        defer { try? library.clear(); try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("selected.m3u")
        let access = ProductAccess(salesEnabled: true, verifiedPro: false)
        for contents in ["not a playlist", "#EXTM3U\nfile:///private/secret.mp4\n", "#EXTM3U\n#EXT-X-TARGETDURATION:10\npart.ts\n"] {
            try Data(contents.utf8).write(to: original)
            XCTAssertThrowsError(try library.importPlaylist(original, name: "Invalid", access: access))
            XCTAssertTrue(library.sources.isEmpty)
        }
        try Data(repeating: 65, count: M3UParser.maximumBytes + 1).write(to: original)
        XCTAssertThrowsError(try library.importPlaylist(original, name: "Oversized", access: access))
        try Data("#EXTM3U\nhttps://example.com/one.mp4\n".utf8).write(to: original)
        XCTAssertThrowsError(try library.add(name: "Outside", kind: .playlistFile, secret: SourceSecret(url: original), access: access))
        try library.importPlaylist(original, name: "Allowed", access: access)
        let source = try XCTUnwrap(library.sources.first)
        let imported = try SourceKeychain.read(source.id).url
        XCTAssertThrowsError(try library.importPlaylist(original, name: "Second", access: access))
        try Data("invalid replacement".utf8).write(to: original)
        XCTAssertThrowsError(try library.importPlaylist(original, name: "Broken", replacing: source, access: access))
        XCTAssertEqual(library.sources, [source])
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        try library.delete(source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testXtreamSourceLoadsEndpointsAndRejectsBadCredentialsOrResponse() async throws {
        let root = "http://127.0.0.1:8769/sources"
        let source = MediaSource(name: "Xtream fixture", kind: .xtream)
        for suffix in ["", "/", "/get.php", "/player_api.php"] {
            let secret = SourceSecret(url: URL(string: root + suffix)!, username: "source+user", password: "source+p&ss")
            let channels = try await SourceLoader.load(source: source, secret: secret)
            XCTAssertEqual(channels.count, 6)
            XCTAssertEqual(channels.first?.group, "Mirivo Demo")
        }
        let pasted = SourceSecret(url: URL(string: root + "/player_api.php?username=source%2Buser&password=source%2Bp%26ss")!)
        let pastedChannels = try await SourceLoader.load(source: source, secret: pasted)
        XCTAssertEqual(pastedChannels.count, 6)
        for secret in [SourceSecret(url: URL(string: root)!, username: "wrong", password: "wrong"),
                       SourceSecret(url: URL(string: root + "/invalid")!, username: "source+user", password: "source+p&ss")] {
            do { _ = try await SourceLoader.load(source: source, secret: secret); XCTFail("Rejected accounts must not become playable channels") }
            catch { XCTAssertTrue(error is LibraryError) }
        }
    }

    func testDirectAndXtreamSourcesDecodeActualHTTPVideo() async throws {
        let direct = MediaSource(name: "Direct fixture", kind: .stream)
        let directChannels = try await SourceLoader.load(source: direct, secret: SourceSecret(url: URL(string: "http://127.0.0.1:8769/demo.mp4")!))
        let xtream = MediaSource(name: "Xtream fixture", kind: .xtream)
        let xtreamChannels = try await SourceLoader.load(source: xtream, secret: SourceSecret(url: URL(string: "http://127.0.0.1:8769/sources")!, username: "source+user", password: "source+p&ss"))
        let model = MirrorModel.shared
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.makeKeyAndVisible()
        defer { model.stopPlayback(); window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        for channel in [try XCTUnwrap(directChannels.first), try XCTUnwrap(xtreamChannels.first)] {
            XCTAssertTrue(model.playMedia(channel))
            let item = try XCTUnwrap(model.playback.player.currentItem)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            item.add(output)
            for _ in 0..<200 {
                if model.playback.currentTime > 0.5 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(model.playback.isPlaying)
            var firstTime = CMTime.invalid
            XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &firstTime))
            try await Task.sleep(for: .milliseconds(600))
            var nextTime = CMTime.invalid
            XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &nextTime))
            XCTAssertGreaterThan(nextTime.seconds, firstTime.seconds + 0.3, "Both entry methods must deliver decoded video frames")
            model.stopPlayback()
        }
    }

    func testPlayingCompatibilityVideoContinuesAfterSeeking() async throws {
        try await checkPlayingVideoSeeks(useCompatibility: true)
    }

    func testPlayingNativeVideoContinuesAfterSeeking() async throws {
        try await checkPlayingVideoSeeks(useCompatibility: false)
    }

    func testOptInProviderMKVSeeksWhilePlaying() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-vod-probe.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("No opt-in MKV fixture") }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        try await checkPlayingVideoSeeks(useCompatibility: true, providerURL: XCTUnwrap(urls["original"]))
    }

    private func checkPlayingVideoSeeks(useCompatibility: Bool, providerURL: URL? = nil) async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(providerURL ?? (useCompatibility
            ? Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")
            : Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Seek fixture", url: url)))
        let playback = model.playback
        let engine = playback.compatibility
        let item = playback.player.currentItem
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item?.add(output)
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<(providerURL == nil ? 150 : 600) {
            if playback.isPlaying && playback.canSeek && playback.currentTime > 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.canSeek)

        // Exercise forward, backward, and overlapping seeks while decoding real video.
        let seeks = providerURL == nil ? [[6.0], [2.0], [3.0, 5.0, 8.0], [2.0, 4.0, 6.0]] : [[120.0], [30.0], [300.0, 600.0, 900.0], [60.0, 180.0, 240.0]]
        for (index, targets) in seeks.enumerated() {
            let target = try XCTUnwrap(targets.last)
            let started = ContinuousClock.now
            for value in targets {
                playback.seek(to: value)
                // Also queue a newer target after the preceding jump has begun.
                if index == 3 { try await Task.sleep(for: .milliseconds(180)) }
            }
            for sample in 0..<(providerURL == nil ? 100 : 400) {
                if playback.currentTime > target + 0.6 && playback.currentTime < target + 3 { break }
                if providerURL != nil, sample.isMultiple(of: 40), let engine, let statistics = engine.mediaPlayer.media?.statistics {
                    print("Seek sample: target=\(target), engineTime=\(engine.mediaTime()), read=\(statistics.readBytes), demux=\(statistics.demuxReadBytes), decoded=\(statistics.decodedVideo), displayed=\(statistics.displayedPictures)")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(playback.isPlaying, "Seeking during playback must preserve play intent")
            XCTAssertGreaterThan(playback.currentTime, target + 0.5, "The timeline must continue after seeking")
            XCTAssertLessThan(playback.currentTime, target + 3, "The newest requested position must win")
            XCTAssertTrue(playback.compatibility === engine)
            XCTAssertTrue(playback.player.currentItem === item)
            if providerURL != nil {
                print("Seek probe: target=\(target), actual=\(playback.currentTime), elapsed=\(started.duration(to: .now)), pictures=\(engine?.mediaPlayer.media?.statistics.displayedPictures ?? 0)")
            }

            if let engine {
                let pictures = engine.mediaPlayer.media?.statistics.displayedPictures ?? 0
                try await Task.sleep(for: .milliseconds(1100))
                XCTAssertGreaterThan(engine.mediaPlayer.media?.statistics.displayedPictures ?? 0, pictures,
                                     "Decoded video must keep reaching the display, not only advance its clock")
            } else if let item {
                var firstTime = CMTime.invalid
                var nextTime = CMTime.invalid
                XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &firstTime))
                try await Task.sleep(for: .milliseconds(600))
                XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &nextTime))
                XCTAssertGreaterThan(nextTime.seconds, firstTime.seconds + 0.3,
                                     "The native video output must produce new frames after seeking")
            }
        }
        if useCompatibility, let engine {
            playback.togglePlayPause()
            for _ in 0..<60 {
                if !playback.isPlaying { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            // An unchanged position must not block the next real seek.
            playback.seek(to: Double(engine.mediaTime()) / 1000)
            try await Task.sleep(for: .milliseconds(250))
            playback.seek(to: providerURL == nil ? 4 : 60)
            for _ in 0..<(providerURL == nil ? 100 : 200) {
                if abs(Double(engine.mediaTime()) / 1000 - (providerURL == nil ? 4 : 60)) < 0.1 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(Double(engine.mediaTime()) / 1000, providerURL == nil ? 4 : 60, accuracy: 0.1)
            XCTAssertFalse(playback.isPlaying, "Queued seeking must not resume an explicitly paused video")
        }
        if providerURL == nil {
            capturePlayer(host.view, name: useCompatibility ? "mkv-after-playing-seeks" : "mp4-after-playing-seeks")
        }
    }

    func testFullscreenVideoUsesEntireViewportAfterRotation() async throws {
        try await checkFullscreenRotation(useCompatibility: true)
    }

    func testNativeFullscreenVideoUsesEntireViewportAfterRotation() async throws {
        try await checkFullscreenRotation(useCompatibility: false)
    }

    private func checkFullscreenRotation(useCompatibility: Bool) async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(useCompatibility
            ? Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")
            : Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            // Restore the app's full supported mask, rather than leaving a
            // portrait geometry preference in the simulator scene session.
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .allButUpsideDown))
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Fullscreen fixture", url: url)))
        let engine = model.playback.compatibility
        let nativeItem = model.playback.player.currentItem
        XCTAssertEqual(engine != nil, useCompatibility)
        for vehicleMode in [false, true] {
            let host = UIHostingController(rootView: VehicleModeView(vehicleMode: vehicleMode, model: model, close: {}))
            window.rootViewController = host
            window.makeKeyAndVisible()
            for orientation: UIInterfaceOrientationMask in [.portrait, .landscapeLeft, .landscapeRight, .portrait] {
                var rotationError: Error?
                host.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { rotationError = $0 }
                let landscape = orientation != .portrait
                for _ in 0..<100 {
                    if (window.bounds.width > window.bounds.height) == landscape { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try await Task.sleep(for: .milliseconds(450))
                // Keep the short fixture on screen throughout both mode/rotation cycles.
                if model.playback.isPlaying {
                    model.playback.togglePlayPause()
                    for _ in 0..<40 {
                        if !model.playback.isPlaying { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
                host.view.layoutIfNeeded()
                XCTAssertNil(rotationError)
                XCTAssertEqual(window.bounds.width > window.bounds.height, landscape)
                let compatibilityView: UIView? = engine?.videoView
                let video = try XCTUnwrap(compatibilityView ?? nativeVideoController(in: host)?.view)
                XCTAssertTrue(video.window === window)
                XCTAssertEqual(video.bounds.width, window.bounds.width, accuracy: 1)
                XCTAssertEqual(video.bounds.height, window.bounds.height, accuracy: 1,
                               "Player chrome must overlay the video, without reducing its height")
                for renderer in engine?.videoView.subviews ?? [] {
                    XCTAssertEqual(renderer.bounds.width, window.bounds.width, accuracy: 1)
                    XCTAssertEqual(renderer.bounds.height, window.bounds.height, accuracy: 1)
                }
                XCTAssertTrue(model.playback.compatibility === engine)
                XCTAssertTrue(model.playback.player.currentItem === nativeItem, "Rotation must not restart playback")
                if orientation == .landscapeLeft {
                    let name = "\(useCompatibility ? "mkv" : "native")-\(vehicleMode ? "vehicle" : "fullscreen")-landscape"
                    capturePlayer(host.view, name: name)
                    if !vehicleMode {
                        model.playback.resume()
                        for _ in 0..<40 {
                            if model.playback.isPlaying { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try await Task.sleep(for: .milliseconds(4700))
                        XCTAssertTrue(model.playback.isPlaying)
                        XCTAssertEqual(video.bounds.size, window.bounds.size, "Hiding controls must not resize video")
                        capturePlayer(host.view, name: "\(name)-unobstructed")
                        model.playback.togglePlayPause()
                    }
                }
            }
        }
    }

    private func nativeVideoController(in controller: UIViewController) -> NativeVideoController? {
        if let player = controller as? NativeVideoController { return player }
        return controller.children.lazy.compactMap { self.nativeVideoController(in: $0) }.first
    }

    private func capturePlayer(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image {
            _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompatibilityVideoHasVisibleInlineOutputBeforeFullscreen() async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Inline fixture", url: url)))
        let engine = try XCTUnwrap(model.playback.compatibility)
        // The existing source-list preview gets the drawable before navigation.
        try await Task.sleep(for: .milliseconds(350))
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(700))
        for _ in 0..<150 {
            if model.playback.currentTime > 0.3 && engine.mediaPlayer.hasVideoOut { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertTrue(engine.mediaPlayer.hasVideoOut)
        XCTAssertTrue(engine.videoView.window === window)
        XCTAssertGreaterThan(engine.videoView.bounds.width, 100)
        XCTAssertGreaterThan(engine.videoView.bounds.height, 80)
        XCTAssertFalse(engine.videoView.subviews.isEmpty)
        for renderView in engine.videoView.subviews {
            XCTAssertEqual(renderView.frame.size.width, engine.videoView.bounds.width, accuracy: 1)
            XCTAssertEqual(renderView.frame.size.height, engine.videoView.bounds.height, accuracy: 1)
        }
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(200))
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let snapshot = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "inline-video-first-open"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompatibilityPiPReturnClearsStaleRendererMask() async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "PiP video", url: url)))
        let engine = try XCTUnwrap(model.playback.compatibility)
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<150 {
            if model.playback.currentTime > 0.3 && engine.mediaPlayer.hasVideoOut { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(300))
        func videoLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
            if let video = layer as? AVSampleBufferDisplayLayer { return video }
            return layer.sublayers?.lazy.compactMap { videoLayer(in: $0) }.first
        }
        let video = try XCTUnwrap(videoLayer(in: engine.videoView.layer))
        XCTAssertFalse(video.preventsCapture, "Capture remains available for the user's device examples")
        // The simulator's VLC build has no system PiP controller. Exercise its
        // didStart/didStop callback contract against the actual decoding layer.
        let pip = PictureInPictureStub()
        engine.configurePiP(pip)
        pip.startPictureInPicture()
        await Task.yield()
        XCTAssertTrue(engine.pipActive)
        let transitionMask = CAShapeLayer()
        transitionMask.path = UIBezierPath(roundedRect: video.bounds, byRoundingCorners: .topLeft,
                                          cornerRadii: CGSize(width: 64, height: 64)).cgPath
        video.mask = transitionMask
        video.cornerRadius = 64
        video.maskedCorners = [.layerMinXMinYCorner]
        let rounding = CABasicAnimation(keyPath: "cornerRadius")
        rounding.fromValue = 64; rounding.toValue = 64; rounding.duration = 10
        video.add(rounding, forKey: "cornerRadius")
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        XCTAssertTrue(video.mask === transitionMask, "Active PiP must retain its transition clipping")
        XCTAssertNotNil(video.animation(forKey: "cornerRadius"))
        pip.stopPictureInPicture()
        await Task.yield()
        XCTAssertFalse(engine.pipActive)
        XCTAssertNil(video.mask, "A completed PiP return must remove the temporary one-corner mask")
        XCTAssertEqual(video.cornerRadius, 0)
        XCTAssertEqual(video.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                           .layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        XCTAssertNil(video.animation(forKey: "cornerRadius"))
        XCTAssertTrue(engine.videoView.window === window)
        XCTAssertTrue(model.playback.compatibility === engine)
        XCTAssertFalse(model.playback.isPlaying, "Restoration must preserve an explicit pause")
        capturePlayer(host.view, name: "inline-player-restored-clipping")
    }

    func testCompatibilityPiPReturnRejectsLateClippingAndKeepsNextPiPUnchanged() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let surface = CompatibilityVideoSurface(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        let renderer = UIView(frame: surface.bounds)
        let video = AVSampleBufferDisplayLayer()
        video.frame = renderer.bounds
        renderer.layer.addSublayer(video)
        surface.addSubview(renderer)
        window.rootViewController?.view.addSubview(surface)
        for height in [220.0, 844.0] {
            surface.frame.size.height = height
            surface.setNeedsLayout(); surface.layoutIfNeeded()
            try await checkLatePiPClipping(video, restore: surface.restoreAfterPictureInPicture,
                                          prepare: surface.prepareForPictureInPicture)
        }
        // VLC can mount a new rendering layer after the return callback.
        surface.restoreAfterPictureInPicture()
        let replacement = UIView(frame: surface.bounds)
        let lateVideo = AVSampleBufferDisplayLayer()
        lateVideo.cornerRadius = 48
        replacement.layer.addSublayer(lateVideo)
        surface.addSubview(replacement)
        XCTAssertEqual(lateVideo.cornerRadius, 0)
        surface.prepareForPictureInPicture()
    }

    func testNativePiPReturnRejectsLateClippingAndKeepsNextPiPUnchanged() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let controller = NativeVideoController(player: AVPlayer(), playback: nil, primary: false)
        controller.loadViewIfNeeded()
        host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
        for height in [220.0, 844.0] {
            controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: height)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            // System PiP is unavailable here. Exercise the same geometry
            // methods used by its delegate with the real AVPlayerLayer.
            try await checkLatePiPClipping(controller.videoLayer, restore: controller.restoreVideoClipping,
                                          prepare: controller.prepareForPictureInPicture)
        }
    }

    func testPiPReturnRepairsRendererWrappersAndChildrenBeforeStopAndPreservesOtherViews() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let surface = CompatibilityVideoSurface(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        window.rootViewController?.view.addSubview(surface)
        let wrapper = UIView(frame: surface.bounds)
        let video = AVSampleBufferDisplayLayer()
        video.frame = wrapper.bounds
        let content = CALayer()
        content.frame = video.bounds
        video.addSublayer(content)
        wrapper.layer.addSublayer(video)
        surface.addSubview(wrapper)
        let subtitle = UIView(frame: surface.bounds)
        subtitle.layer.cornerRadius = 12
        let subtitleMask = CALayer()
        subtitle.layer.mask = subtitleMask
        surface.addSubview(subtitle)

        // The old cleanup visited only the AVSampleBufferDisplayLayer. A
        // rounded parent or renderer child continued to clip the same picture.
        for height in [220.0, 844.0] {
            surface.frame.size.height = height
            surface.prepareForPictureInPicture()
            for layer in [surface.layer, wrapper.layer, content] { layer.cornerRadius = 64 }
            surface.restoreAfterPictureInPicture()
            for layer in [surface.layer, wrapper.layer, content] {
                XCTAssertEqual(layer.cornerRadius, 0)
                try await checkLatePiPClipping(layer, restore: surface.restoreAfterPictureInPicture,
                                              prepare: surface.prepareForPictureInPicture)
            }
            XCTAssertEqual(subtitle.layer.cornerRadius, 12, "Non-video sibling geometry must be preserved")
            XCTAssertTrue(subtitle.layer.mask === subtitleMask)
        }
        surface.restoreAfterPictureInPicture()
        let lateContent = CALayer()
        lateContent.cornerRadius = 36
        video.addSublayer(lateContent)
        XCTAssertEqual(lateContent.cornerRadius, 0, "Observe newly attached renderer children before the next frame")
        surface.prepareForPictureInPicture()
    }

    func testPiPButtonReturnWaitsForLayoutAndAvoidsASecondStop() async throws {
        let playback = PlaybackController()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "Return handoff", live: false, useCompatibility: true)
        let engine = try XCTUnwrap(playback.compatibility)
        let window = try mountCompatibilityPiPSource(engine)
        defer { window.isHidden = true; window.rootViewController = nil }
        let video = AVSampleBufferDisplayLayer()
        engine.videoView.layer.addSublayer(video)
        let pip = PictureInPictureStub()
        engine.configurePiP(pip)
        playback.applicationDidEnterBackground()
        await Task.yield()
        XCTAssertTrue(engine.pipActive)
        video.cornerRadius = 64
        XCTAssertEqual(video.cornerRadius, 64)
        playback.applicationWillEnterForeground()
        XCTAssertEqual(video.cornerRadius, 64, "Foreground layout must not fight the in-flight system transition")
        XCTAssertTrue(engine.pipActive)
        XCTAssertEqual(pip.stopCount, 0)
        video.cornerRadius = 40
        XCTAssertEqual(video.cornerRadius, 40)
        var restored = false
        engine.onRestore? { restored = $0 }
        XCTAssertFalse(restored, "onAppear alone must not complete restoration before UIKit commits the source layout")
        playback.applicationDidBecomeActive()
        for _ in 0..<50 {
            if restored { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(restored)
        XCTAssertEqual(pip.stopCount, 0, "The PiP return button already owns the stop animation")
        XCTAssertEqual(video.cornerRadius, 40)
        pip.stopPictureInPicture()
        XCTAssertFalse(engine.pipActive)
        XCTAssertEqual(pip.stopCount, 1)
        XCTAssertEqual(video.cornerRadius, 0, "Repair begins when AVKit has finished its transition")
    }

    private func mountCompatibilityPiPSource(_ engine: CompatibilityPlayback) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        let host = CompatibilityVideoHost(frame: CGRect(x: 20, y: 120, width: 350, height: 197))
        root.view.addSubview(host)
        host.configure(engine: engine, role: .inline, fillsFrame: false)
        window.layoutIfNeeded()
        return window
    }

    private func checkLatePiPClipping(_ video: CALayer, restore: () -> Void, prepare: () -> Void) async throws {
        let radius = CABasicAnimation(keyPath: "cornerRadius")
        radius.fromValue = 64; radius.toValue = 0; radius.duration = 1
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.8; opacity.toValue = 1; opacity.duration = 1
        let group = CAAnimationGroup()
        group.animations = [radius, opacity]; group.duration = 1
        video.add(group, forKey: "system-return-transition")
        restore()
        let remaining = try XCTUnwrap(video.animation(forKey: "system-return-transition") as? CAAnimationGroup)
        XCTAssertEqual(remaining.animations?.count, 1)
        XCTAssertEqual((remaining.animations?.first as? CAPropertyAnimation)?.keyPath, "opacity",
                       "Removing a grouped corner animation must preserve unrelated animation")

        // This happens AFTER didStop, when the old single cleanup already ran.
        try await Task.sleep(for: .milliseconds(120))
        video.cornerRadius = 48
        video.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 390, height: 220), cornerRadius: 48).cgPath
        video.mask = mask
        XCTAssertEqual(video.cornerRadius, 0, "Late radius changes must be corrected synchronously")
        XCTAssertNil(video.mask)
        XCTAssertEqual(video.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                            .layerMinXMaxYCorner, .layerMaxXMaxYCorner])

        // A later explicit animation can round the presentation while the
        // model radius is already zero, so no KVO change is emitted.
        video.add(radius, forKey: "late-return-animation")
        for _ in 0..<20 {
            if video.animation(forKey: "late-return-animation") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(video.animation(forKey: "late-return-animation"))
        prepare()
        video.cornerRadius = 32
        video.mask = mask
        video.add(radius, forKey: "next-pip-animation")
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(video.cornerRadius, 32, "A new system PiP transition must retain its own geometry")
        XCTAssertTrue(video.mask === mask)
        XCTAssertNotNil(video.animation(forKey: "next-pip-animation"))
    }

    func testBackgroundPiPWaitsForCompatibilityRendererAndKeepsPauseAndTVRouting() async throws {
        let playback = PlaybackController()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "PiP readiness", live: false, useCompatibility: true)
        for _ in 0..<150 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        let engine = try XCTUnwrap(playback.compatibility)
        // Keep the source detached until a deterministic PiP controller is ready.
        playback.applicationDidEnterBackground()
        XCTAssertTrue(playback.pendingAutomaticPiP)
        let pip = PictureInPictureStub()
        engine.configurePiP(pip)
        let window = try mountCompatibilityPiPSource(engine)
        defer { window.isHidden = true; window.rootViewController = nil }
        await Task.yield()
        XCTAssertEqual(pip.startCount, 1)
        XCTAssertTrue(engine.pipActive)
        XCTAssertFalse(playback.pendingAutomaticPiP)
        playback.togglePlayPause()
        for _ in 0..<40 {
            if !playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        playback.applicationDidEnterBackground()
        XCTAssertFalse(playback.pendingAutomaticPiP)
        XCTAssertEqual(pip.startCount, 1)
        // App-icon return restores the existing UI before it stops PiP. A pause
        // in PiP must survive this handoff without replacing the decoder.
        var restoration: ((Bool) -> Void)?
        playback.onRestorePlayer = { restoration = $0 }
        playback.applicationDidBecomeActive()
        XCTAssertNotNil(restoration)
        XCTAssertEqual(pip.stopCount, 0)
        XCTAssertTrue(engine.pipActive)
        restoration?(true)
        for _ in 0..<50 {
            if pip.stopCount == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(pip.stopCount, 1)
        XCTAssertFalse(engine.pipActive)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.compatibility === engine)
        playback.onRestorePlayer = nil
        playback.resume()
        for _ in 0..<40 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        playback.applicationDidEnterBackground()
        await Task.yield()
        XCTAssertEqual(pip.startCount, 2)
        playback.applicationDidBecomeActive()
        for _ in 0..<50 {
            if pip.stopCount == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(pip.stopCount, 2)
        XCTAssertFalse(engine.pipActive)
        XCTAssertTrue(playback.isPlaying)
        playback.externalDisplayConnected = true
        playback.applicationDidEnterBackground()
        XCTAssertFalse(playback.pendingAutomaticPiP)
        XCTAssertFalse(playback.canStartPictureInPicture)
        XCTAssertEqual(pip.startCount, 2)
    }

    func testForegroundPiPReturnHandlesLateStartAndCancelledBackgroundRequest() async throws {
        let playback = PlaybackController()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "PiP race", live: false, useCompatibility: true)
        let engine = try XCTUnwrap(playback.compatibility)
        playback.applicationDidEnterBackground()
        XCTAssertTrue(playback.pendingAutomaticPiP)
        playback.applicationDidBecomeActive()
        let pip = PictureInPictureStub()
        pip.completesStartImmediately = false
        engine.configurePiP(pip)
        let window = try mountCompatibilityPiPSource(engine)
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertEqual(pip.startCount, 0, "A renderer ready after foreground must not start a cancelled request")

        playback.applicationDidEnterBackground()
        XCTAssertEqual(pip.startCount, 1)
        playback.applicationDidBecomeActive()
        XCTAssertEqual(pip.stopCount, 0)
        pip.stateChangeEventHandler?(true)
        for _ in 0..<20 {
            if pip.stopCount == 1 && !engine.pipActive { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(pip.stopCount, 1, "A PiP start completing after foreground must return to the app")
        XCTAssertFalse(engine.pipActive)

        playback.startPictureInPicture()
        pip.stateChangeEventHandler?(true)
        await Task.yield()
        XCTAssertTrue(engine.pipActive, "A later explicit PiP request must remain open")
        XCTAssertEqual(pip.stopCount, 1)
        playback.applicationDidBecomeActive()
        XCTAssertEqual(pip.stopCount, 1, "Temporary inactivity without backgrounding must not close explicit PiP")
        var restoration: ((Bool) -> Void)?
        playback.onRestorePlayer = { restoration = $0 }
        playback.applicationDidEnterBackground()
        playback.applicationDidBecomeActive()
        XCTAssertNotNil(restoration)
        playback.stop()
        let stopsBeforeLateRestore = pip.stopCount
        restoration?(true)
        XCTAssertEqual(pip.stopCount, stopsBeforeLateRestore, "An old restoration must not act after playback stops")
    }

    func testCompatibilityCaptureProtectionIncludesNestedAndLateVideoLayers() {
        let surface = CompatibilityVideoSurface()
        surface.captureProtectionEnabled = true
        let renderer = UIView()
        let wrapper = CALayer()
        let video = AVSampleBufferDisplayLayer()
        wrapper.addSublayer(video)
        renderer.layer.addSublayer(wrapper)
        surface.addSubview(renderer)
        XCTAssertTrue(video.preventsCapture)
        let lateVideo = AVSampleBufferDisplayLayer()
        wrapper.addSublayer(lateVideo)
        surface.setNeedsLayout(); surface.layoutIfNeeded()
        XCTAssertTrue(lateVideo.preventsCapture)
        surface.restoreAfterPictureInPicture()
        XCTAssertTrue(video.preventsCapture)
        XCTAssertTrue(lateVideo.preventsCapture)
        surface.captureProtectionEnabled = false
        XCTAssertFalse(video.preventsCapture)
        XCTAssertFalse(lateVideo.preventsCapture)
    }

    func testCaptureIsTemporarilyAllowedForPiPCornerExamples() {
        let surface = CompatibilityVideoSurface()
        let renderer = UIView()
        let video = AVSampleBufferDisplayLayer()
        video.preventsCapture = true
        renderer.layer.addSublayer(video)
        surface.addSubview(renderer)
        XCTAssertFalse(video.preventsCapture, "Diagnostic builds must allow examples from the device")
        let lateVideo = AVSampleBufferDisplayLayer()
        lateVideo.preventsCapture = true
        renderer.layer.addSublayer(lateVideo)
        surface.setNeedsLayout(); surface.layoutIfNeeded()
        surface.restoreAfterPictureInPicture()
        XCTAssertFalse(lateVideo.preventsCapture)
        XCTAssertFalse(video.preventsCapture)
    }

    private final class PictureInPictureStub: NSObject, VLCPictureInPictureWindowControlling {
        var stateChangeEventHandler: ((Bool) -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var completesStartImmediately = true
        func startPictureInPicture() {
            startCount += 1
            if completesStartImmediately { stateChangeEventHandler?(true) }
        }
        func stopPictureInPicture() { stopCount += 1; stateChangeEventHandler?(false) }
        func invalidatePlaybackState() {}
    }

    func testPiPSourcesFitThePictureWithoutLetterboxAndStillSupportFill() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let nativeURL = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let player = AVPlayer(url: nativeURL)
        player.isMuted = true
        let controller = NativeVideoController(player: player, playback: nil, primary: false)
        root.addChild(controller); root.view.addSubview(controller.view); controller.didMove(toParent: root)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        player.play()
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        for _ in 0..<100 {
            if controller.videoLayer.isReadyForDisplay && (player.currentItem?.presentationSize.width ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(controller.videoLayer.isReadyForDisplay)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.videoLayer.frame.minY, 0)
        XCTAssertLessThan(controller.videoLayer.frame.height, controller.view.bounds.height)
        XCTAssertEqual(controller.videoLayer.videoRect.width, controller.videoLayer.bounds.width, accuracy: 1)
        XCTAssertEqual(controller.videoLayer.videoRect.height, controller.videoLayer.bounds.height, accuracy: 1)
        controller.videoLayer.videoGravity = .resizeAspectFill
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.videoLayer.frame, controller.view.bounds)

        let engine = CompatibilityPlayback()
        defer { engine.stop() }
        let host = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        host.configure(engine: engine, role: .fullscreen, fillsFrame: false)
        root.view.addSubview(host)
        engine.open(try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")))
        for _ in 0..<150 {
            if engine.mediaPlayer.hasVideoOut && engine.mediaPlayer.videoSize.width > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(engine.mediaPlayer.hasVideoOut)
        host.setNeedsLayout(); host.layoutIfNeeded()
        XCTAssertTrue(engine.videoView.superview === host)
        XCTAssertGreaterThan(engine.videoView.frame.minY, 0)
        XCTAssertLessThan(engine.videoView.frame.height, host.bounds.height)
        let fitted = engine.videoView.frame
        host.configure(engine: engine, role: .fullscreen, fillsFrame: true)
        XCTAssertEqual(engine.videoView.frame, host.bounds)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .larger)
        host.configure(engine: engine, role: .fullscreen, fillsFrame: false)
        XCTAssertEqual(engine.videoView.frame, fitted)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .smaller)
        XCTAssertTrue(engine.mediaPlayer.hasVideoOut, "Fit changes must retain the running decoder")
    }

    func testCompatibilityVideoOwnershipSurvivesPreviewUpdatesAndFullscreenReturn() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let root = try XCTUnwrap(window.rootViewController?.view)
        let engine = CompatibilityPlayback()
        let preview = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 88, height: 50))
        preview.configure(engine: engine, role: .preview, fillsFrame: false)
        root.addSubview(preview)
        XCTAssertTrue(engine.videoView.superview === preview)

        // Do not move the renderer into an inline host until it has real bounds.
        let inline = CompatibilityVideoHost()
        inline.configure(engine: engine, role: .inline, fillsFrame: false)
        root.addSubview(inline)
        XCTAssertTrue(engine.videoView.superview === preview)
        inline.frame = CGRect(x: 0, y: 100, width: 320, height: 180)
        inline.layoutIfNeeded()
        XCTAssertTrue(engine.videoView.superview === inline)
        XCTAssertEqual(engine.videoView.bounds.size, inline.bounds.size)

        preview.configure(engine: engine, role: .preview, fillsFrame: false)
        XCTAssertTrue(engine.videoView.superview === inline, "A stale preview update must not steal the video")
        let fullscreen = CompatibilityVideoHost(frame: root.bounds)
        fullscreen.configure(engine: engine, role: .fullscreen, fillsFrame: true)
        root.addSubview(fullscreen)
        inline.configure(engine: engine, role: .inline, fillsFrame: false)
        XCTAssertTrue(engine.videoView.superview === fullscreen)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .larger)
        fullscreen.detach()
        XCTAssertTrue(engine.videoView.superview === inline)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .smaller)
        inline.removeFromSuperview()
        XCTAssertTrue(engine.videoView.superview === preview, "Returning to the list must restore its preview")
        fullscreen.removeFromSuperview()
        XCTAssertTrue(engine.videoView.superview === preview, "Late teardown must not detach the new owner")
        preview.detach()
        XCTAssertNil(engine.videoView.superview)
    }

    func testNativeTimelineShowsDurationSeeksWhilePausedAndResets() async throws {
        let url = try audioFixture()
        let playback = PlaybackController()
        defer { playback.stop(); try? FileManager.default.removeItem(at: url) }
        // Metadata must identify finite media even when its URL was classified as live.
        try playback.play(url: url, requiresExternalPlayback: false, live: true, presentation: .audio)
        for _ in 0..<100 {
            if playback.currentTime > 0.1 && playback.canSeek { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(playback.currentTime, 0.1)
        XCTAssertEqual(playback.duration, 10, accuracy: 0.1)
        XCTAssertFalse(playback.isLive)
        XCTAssertTrue(playback.canSeek)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        playback.seek(to: 6)
        for _ in 0..<100 {
            if abs(playback.player.currentTime().seconds - 6) < 0.1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.player.currentTime().seconds, 6, accuracy: 0.1)
        XCTAssertEqual(playback.currentTime, 6, accuracy: 0.1)
        XCTAssertFalse(playback.isPlaying, "Seeking must not undo a user pause")
        let metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(metadata?[MPMediaItemPropertyPlaybackDuration] as? Double, 10)
        XCTAssertEqual(metadata?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false)
        playback.stop()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertEqual(playback.duration, 0)
        XCTAssertFalse(playback.canSeek)
    }

    func testCompatibilityTimelineSeeksAndIgnoresReplacedEngine() async throws {
        let url = try audioFixture()
        let playback = PlaybackController()
        defer { playback.stop(); try? FileManager.default.removeItem(at: url) }
        try playback.play(url: url, requiresExternalPlayback: false, live: false, presentation: .audio, useCompatibility: true)
        let engine = try XCTUnwrap(playback.compatibility)
        for _ in 0..<150 {
            if playback.currentTime > 0.1 && playback.canSeek { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(playback.currentTime, 0.1)
        XCTAssertEqual(playback.duration, 10, accuracy: 0.1)
        XCTAssertFalse(playback.isLive)
        XCTAssertTrue(playback.canSeek)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(200))
        playback.seek(to: 6)
        for _ in 0..<100 {
            if abs(Double(engine.mediaTime()) / 1000 - 6) < 0.25 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(Double(engine.mediaTime()) / 1000, 6, accuracy: 0.25)
        XCTAssertFalse(playback.isPlaying)
        try playback.play(url: url, requiresExternalPlayback: false, live: true, presentation: .audio)
        engine.onTime?(99, 100)
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertEqual(playback.duration, 0)
        XCTAssertTrue(playback.isLive)
    }

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

    func testVideoPlaysOnPhoneWithoutCarConnection() async throws {
        let model = MirrorModel.shared
        model.stopPlayback()
        defer { model.stopPlayback() }
        XCTAssertFalse(model.carPlayConnected)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Local video", url: url)))
        XCTAssertEqual(model.playback.state, .loading)
        XCTAssertFalse(model.playback.canUseVehicleMode)
        for _ in 0..<100 {
            if model.playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertEqual(model.playback.state, .playing)
        XCTAssertNil(model.mediaErrorMessage)
        XCTAssertFalse(model.playback.externalPlaybackActive)
        XCTAssertFalse(model.playback.player.isMuted)
    }

    func testFailedMediaClearsNowPlayingAndRetainsRetryAfterDismissingAlert() async throws {
        let model = MirrorModel.shared
        model.stopPlayback()
        defer { model.stopPlayback() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).mp4")
        let channel = MediaChannel(title: "Unavailable stream", url: url)
        XCTAssertTrue(model.playMedia(channel))
        for _ in 0..<100 {
            if model.playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.playback.state, .failed)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNil(model.playback.player.currentItem)
        XCTAssertFalse(model.playback.hasActivePlayback)
        XCTAssertFalse(model.playback.canUseVehicleMode)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertNotNil(model.errorMessage)
        model.errorMessage = nil
        XCTAssertNotNil(model.mediaErrorMessage)
        XCTAssertEqual(model.selectedMediaChannel, channel)
        model.retryMedia()
        XCTAssertEqual(model.playback.state, .loading)
        XCTAssertNotNil(model.playback.player.currentItem)
        XCTAssertNil(model.mediaErrorMessage)
        model.stopPlayback()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.playback.state, .idle)
        XCTAssertNil(model.selectedMediaChannel)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNil(model.mediaErrorMessage)
    }

    func testChannelQueuePreservesActiveSessionAndMovesBetweenChannels() throws {
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = MediaChannel(title: "Queue first", url: url)
        let second = MediaChannel(title: "Queue second", url: url.appendingPathComponent("second"))
        XCTAssertTrue(model.playMedia(first, queue: [first, second]))
        let item = try XCTUnwrap(model.playback.player.currentItem)
        XCTAssertTrue(model.playMedia(first))
        XCTAssertTrue(model.playback.player.currentItem === item)
        XCTAssertNil(model.adjacentChannel(-1))
        XCTAssertEqual(model.adjacentChannel(1), second)
        model.switchChannel(1)
        XCTAssertEqual(model.selectedMediaChannel, second)
        XCTAssertEqual(model.adjacentChannel(-1), first)
        XCTAssertNil(model.adjacentChannel(1))
    }

    func testChannelSelectionKeepsPiPRestoredPlayerPresented() throws {
        let model = MirrorModel.shared
        let url = try audioFixture()
        defer { model.stopPlayback(); try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "First", url: url)))
        model.playerVisibilityChanged(false)
        model.playback.onRestorePlayer? { _ in }
        XCTAssertTrue(model.presentingPlayer)
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Second", url: url)))
        XCTAssertTrue(model.presentingPlayer, "Picking a channel must keep the restored player's full-screen presentation open")
        XCTAssertEqual(model.mediaTitle, "Second")
    }

    func testLateFailureFromReplacedItemDoesNotStopNewPlayback() async throws {
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "First", url: url)))
        let oldItem = try XCTUnwrap(model.playback.player.currentItem)
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Second", url: url)))
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: oldItem)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.mediaTitle, "Second")
        XCTAssertNil(model.mediaErrorMessage)
        let currentItem = try XCTUnwrap(model.playback.player.currentItem)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: currentItem)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.playback.state, .failed)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNotNil(model.mediaErrorMessage)
    }

    // Opt-in provider regression: a local, untracked fixture in the simulator app's tmp
    // directory supplies `ts` and `m3u8` URLs. Never put account URLs in test sources/logs.
    func testOptInProviderTransportStreamAndHLSPlayback() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-live-playback-fixture.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("No opt-in live provider fixture")
        }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        let transportStream = try XCTUnwrap(urls["ts"])
        let hls = try XCTUnwrap(urls["m3u8"])
        let playback = PlaybackController()
        defer { playback.stop() }
        var failure: DiagnosticFailure?
        playback.onDiagnostic = { kind, values in
            if kind == .failure { failure = values.failure }
        }
        try playback.play(url: transportStream, preserveSourceAudio: false, requiresExternalPlayback: false)
        for _ in 0..<200 {
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(playback.state, .failed)
        XCTAssertEqual(failure?.code, -11850)
        try playback.play(url: hls, preserveSourceAudio: false, requiresExternalPlayback: false)
        for _ in 0..<200 {
            if playback.isPlaying && playback.player.currentTime().seconds > 0.2 { break }
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.player.currentTime().seconds, 0.2)
        XCTAssertGreaterThan(playback.player.currentItem?.presentationSize.width ?? 0, 0)
        XCTAssertNil(playback.errorMessage)
    }

    func testSourceCacheReusesResultsAndInvalidatesOnEdit() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Fixture", kind: .playlist)
        let channel = MediaChannel(title: "One", url: URL(string: "https://example.com/one.m3u8")!)
        var requests = 0
        let first = try await cache.channels(for: source) { requests += 1; return [channel] }
        let second = try await cache.channels(for: source) { requests += 1; return [] }
        XCTAssertEqual(first, second)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(cache.cached(for: source), [channel])
        cache.invalidate(source.id)
        XCTAssertNil(cache.cached(for: source))
        _ = try await cache.channels(for: source) { requests += 1; return [channel] }
        XCTAssertEqual(requests, 2)
        cache.removeAll()
        XCTAssertNil(cache.cached(for: source))
    }

    func testAccountExpiryPersistsWithoutSecretsAndRefreshesAfterTTL() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("expiry-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let source = MediaSource(name: "IPTV fixture", kind: .xtream)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calls = 0
        let store = SourceAccountStore(file: file) { _ in
            calls += 1
            return IPTVAccountInfo(expiresAt: now.addingTimeInterval(Double(calls) * 86_400))
        }
        await store.refresh(for: source, now: now)
        await store.refresh(for: source, now: now.addingTimeInterval(899))
        XCTAssertEqual(calls, 1)
        let restored = SourceAccountStore(file: file)
        XCTAssertEqual(restored.state(for: source), store.state(for: source))
        let data = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
        await store.refresh(for: source, now: now.addingTimeInterval(901))
        XCTAssertEqual(calls, 2)
        guard case .information(let snapshot, false) = store.state(for: source) else { return XCTFail("Expected refreshed date") }
        XCTAssertEqual(snapshot.info.expiresAt, now.addingTimeInterval(2 * 86_400))
        store.invalidate(source.id)
        XCTAssertNil(store.state(for: source))
        XCTAssertNil(SourceAccountStore(file: file).state(for: source))
    }

    func testAccountExpiryFailureKeepsLastKnownDateAndAllowsRetry() async throws {
        let source = MediaSource(name: "IPTV fixture", kind: .xtream)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fail = false
        var calls = 0
        let store = SourceAccountStore { _ in
            calls += 1
            if fail { throw LibraryError.invalidResponse }
            return IPTVAccountInfo(expiresAt: now.addingTimeInterval(86_400))
        }
        await store.refresh(for: source, now: now)
        fail = true
        await store.refresh(for: source, force: true, now: now.addingTimeInterval(901))
        guard case .information(let snapshot, true) = store.state(for: source) else { return XCTFail("Keep cached date with failure flag") }
        XCTAssertEqual(snapshot.checkedAt, now)
        await store.refresh(for: source, now: now.addingTimeInterval(930))
        XCTAssertEqual(calls, 2, "Avoid repeated failing requests")
        fail = false
        await store.refresh(for: source, now: now.addingTimeInterval(962))
        XCTAssertEqual(calls, 3)
        guard case .information(_, false) = store.state(for: source) else { return XCTFail("Clear failure after retry") }
    }

    func testSourceCredentialEditRefreshesExpiryWithoutRenaming() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("expiry-library-\(UUID())")
        let library = SourceLibrary(directory: directory) { source in
            let secret = try SourceKeychain.read(source.id)
            return IPTVAccountInfo(expiresAt: Date(timeIntervalSince1970: secret.username == "renewed" ? 1_900_000_000 : 1_800_000_000))
        }
        defer { try? library.clear(); try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://example.com")!
        try library.add(name: "Same source", kind: .xtream, secret: SourceSecret(url: url, username: "initial", password: "fixture"),
                        access: ProductAccess(salesEnabled: false, verifiedPro: false))
        let source = try XCTUnwrap(library.sources.first)
        await library.accounts.refresh(for: source)
        try library.update(source, name: source.name, kind: source.kind,
                           secret: SourceSecret(url: url, username: "renewed", password: "fixture"))
        XCTAssertEqual(library.sources.first, source, "Editing credentials keeps the SwiftUI task's source key unchanged")
        for _ in 0..<40 {
            if case .information = library.accounts.state(for: source) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard case .information(let snapshot, false) = library.accounts.state(for: source) else { return XCTFail("Credential edits must trigger a refresh") }
        XCTAssertEqual(snapshot.info.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
        try library.delete(source)
        XCTAssertNil(library.accounts.state(for: source))
    }

    func testAccountExpiryCoalescesAndDiscardsDeletedSourceResponse() async throws {
        let source = MediaSource(name: "Slow", kind: .xtream)
        var requests = 0
        let store = SourceAccountStore { _ in
            requests += 1
            try? await Task.sleep(for: .milliseconds(100))
            return IPTVAccountInfo(expiresAt: .distantFuture)
        }
        let first = Task { await store.refresh(for: source) }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { await store.refresh(for: source) }
        try await Task.sleep(for: .milliseconds(20))
        store.invalidate(source.id)
        await first.value; await second.value
        XCTAssertEqual(requests, 1)
        XCTAssertNil(store.state(for: source))
        await store.refresh(for: source)
        XCTAssertNotNil(store.state(for: source))
        store.removeAll()
        XCTAssertNil(store.state(for: source))
    }

    func testAccountExpiryUnsupportedAndFailedLoadsDoNotAffectChannelCache() async throws {
        let source = MediaSource(name: "Plain M3U", kind: .playlist)
        let channels = SourceChannelCache()
        let channel = MediaChannel(title: "One", url: URL(string: "https://example.com/live.m3u8")!)
        _ = try await channels.channels(for: source) { [channel] }
        let unsupported = SourceAccountStore { _ in nil }
        await unsupported.refresh(for: source)
        XCTAssertEqual(unsupported.state(for: source), .unsupported)
        let failed = SourceAccountStore { _ in throw LibraryError.invalidResponse }
        await failed.refresh(for: source)
        XCTAssertEqual(failed.state(for: source), .failed)
        XCTAssertEqual(channels.cached(for: source), [channel])
    }

    func testSourceCacheCoalescesConcurrentLoads() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Concurrent", kind: .playlist)
        var requests = 0
        let first = Task { try await cache.channels(for: source) {
            requests += 1
            try await Task.sleep(for: .milliseconds(100))
            return []
        } }
        await Task.yield()
        let second = Task { try await cache.channels(for: source) { requests += 1; return [] } }
        _ = try await first.value; _ = try await second.value
        XCTAssertEqual(requests, 1)
    }

    func testSourceCacheDoesNotPublishAnInvalidatedInFlightResponse() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Invalidated", kind: .playlist)
        let channel = MediaChannel(title: "Old", url: URL(string: "https://example.com/old.m3u8")!)
        let old = Task { try await cache.channels(for: source) {
            try? await Task.sleep(for: .milliseconds(100))
            return [channel]
        } }
        try await Task.sleep(for: .milliseconds(20))
        cache.invalidate(source.id)
        do { _ = try await old.value; XCTFail("Invalidated response must be discarded") }
        catch is CancellationError { }
        XCTAssertNil(cache.cached(for: source))
        let fresh = try await cache.channels(for: source) { [] }
        XCTAssertTrue(fresh.isEmpty)
    }

    func testBackgroundPolicyAndPiPRestorationKeepCurrentItem() async throws {
        let model = MirrorModel.shared
        let url = try audioFixture()
        defer { model.stopPlayback(); try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Background", url: url)))
        let item = model.playback.player.currentItem
        XCTAssertEqual(model.playback.player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        model.playerVisibilityChanged(false)
        var restored = false
        model.playback.onRestorePlayer? { restored = $0 }
        XCTAssertTrue(model.presentingPlayer)
        XCTAssertFalse(restored)
        model.playerVisibilityChanged(true)
        XCTAssertTrue(restored)
        XCTAssertTrue(item === model.playback.player.currentItem)
        model.presentingPlayer = false
        model.playerVisibilityChanged(false)
    }

    func testOptInProviderMKVPlayback() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-vod-probe.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("No opt-in MKV fixture") }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        let url = try XCTUnwrap(urls["original"])
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let channel = MediaChannel(title: "MKV fixture", url: url)
        XCTAssertTrue(channel.requiresCompatibilityPlayback)
        XCTAssertFalse(channel.isLive)
        XCTAssertTrue(model.playMedia(channel))
        let engine = try XCTUnwrap(model.playback.compatibility)
        engine.videoView.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        for _ in 0..<300 {
            if model.playback.isPlaying && model.playback.currentTime > 0.2 { break }
            if model.playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertGreaterThan(model.playback.currentTime, 0.2)
        XCTAssertGreaterThan(engine.mediaPlayer.videoSize.width, 0)
        XCTAssertNil(model.mediaErrorMessage)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false)
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.playback.isPlaying)
        model.foregrounded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.playback.isPlaying, "Foregrounding must not undo a user pause")
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.playback.isPlaying)
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
