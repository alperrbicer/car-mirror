import XCTest
@testable import MirrorCore

final class CarPlayMediaPolicyTests: XCTestCase {
    private func packet(pid: Int, time: Double?, counter: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0xff, count: 188)
        bytes[0] = 0x47
        bytes[1] = UInt8(pid >> 8) | (time == nil ? 0 : 0x40)
        bytes[2] = UInt8(pid & 0xff)
        bytes[3] = 0x10 | counter
        if let time {
            let ticks = UInt64(time * 90_000)
            bytes.replaceSubrange(4..<13, with: [0, 0, 1, 0xe0, 0, 0, 0x80, 0x80, 5])
            bytes[13] = UInt8((ticks >> 29) & 0x0e) | 0x21
            bytes[14] = UInt8((ticks >> 22) & 0xff)
            bytes[15] = UInt8((ticks >> 14) & 0xfe) | 1
            bytes[16] = UInt8((ticks >> 7) & 0xff)
            bytes[17] = UInt8((ticks << 1) & 0xfe) | 1
        }
        return Data(bytes)
    }

    func testVODSegmentDropsInitialPESFramesBeforeTheSeekPosition() throws {
        let tables = packet(pid: 0, time: nil, counter: 0)
        let initial = packet(pid: 256, time: 0.4, counter: 0)
        let initialTail = packet(pid: 256, time: nil, counter: 1)
        let target = packet(pid: 256, time: 16.4, counter: 2)
        let tail = packet(pid: 256, time: nil, counter: 3)
        let source = tables + initial + initialTail + target + tail
        let result = try CarPlayVODPlaylist.removingSeekPreroll(from: source, before: 16)
        XCTAssertEqual(result, tables + packet(pid: 256, time: 0.4, counter: 2) + tail,
                       "Drop initial PES units and restart the transport clock at the requested segment")
        XCTAssertEqual(try CarPlayVODPlaylist.removingSeekPreroll(from: source, before: 0), source)
        XCTAssertThrowsError(try CarPlayVODPlaylist.removingSeekPreroll(from: Data([0x47]), before: 16))
        XCTAssertThrowsError(try CarPlayVODPlaylist.removingSeekPreroll(from: source, before: .nan))
    }

    func testVODSegmentKeepsFramesOnALocalClockAndTrimsAtItsAdvertisedDuration() throws {
        let tables = packet(pid: 0, time: nil, counter: 0)
        let times = (0...7).map { Double($0) + 0.4 }
        let frames = times.enumerated().map { packet(pid: 256, time: $0.element, counter: UInt8($0.offset)) }
        let source = frames.reduce(tables, +)
        let firstSix = frames.prefix(6).reduce(tables, +)
        for start in [0.0, 6.0, 12.0] {
            XCTAssertEqual(try CarPlayVODPlaylist.removingSeekPreroll(from: source, before: start, duration: 6), firstSix)
        }
        XCTAssertEqual(try CarPlayVODPlaylist.removingSeekPreroll(from: firstSix, before: 12, duration: 6), firstSix)
        XCTAssertThrowsError(try CarPlayVODPlaylist.removingSeekPreroll(from: tables, before: 12, duration: 6))
    }

    func testVODPlaylistDescribesTheWholeEpisodeInsteadOfALiveWindow() throws {
        let playlist = try CarPlayVODPlaylist(duration: 3_441, startPosition: 31)
        let manifest = String(decoding: playlist.manifest, as: UTF8.self)
        XCTAssertTrue(manifest.contains("#EXT-X-PLAYLIST-TYPE:VOD\n"))
        XCTAssertTrue(manifest.contains("#EXT-X-TARGETDURATION:6\n"))
        XCTAssertTrue(manifest.hasSuffix("#EXT-X-ENDLIST\n"))
        XCTAssertTrue(manifest.contains("TIME-OFFSET=31.000000,PRECISE=YES"))
        XCTAssertEqual(playlist.segmentCount, 574)
        XCTAssertEqual(playlist.interval(for: 0), 0..<6)
        XCTAssertEqual(playlist.interval(for: 1), 6..<12)
        XCTAssertEqual(playlist.interval(for: 573), 3_438..<3_441)
        for time in [0.0, 5.999, 6, 11.999, 12, 31, 3_440.999] {
            XCTAssertTrue(try XCTUnwrap(playlist.interval(for: playlist.index(at: time))).contains(time))
        }
        XCTAssertEqual(playlist.index(at: .infinity), 0)
        XCTAssertEqual(playlist.index(at: 90_000), playlist.segmentCount - 1)
        XCTAssertEqual(manifest.components(separatedBy: "#EXTINF:").count - 1, playlist.segmentCount)
        let lengths = (0..<playlist.segmentCount).compactMap { playlist.interval(for: $0) }.map { $0.upperBound - $0.lowerBound }
        XCTAssertEqual(lengths.reduce(0, +), playlist.duration)
        XCTAssertLessThan(playlist.manifest.count, 1_048_576)
    }

    func testVODSegmentRequestsAreBoundedAndCanonical() throws {
        let playlist = try CarPlayVODPlaylist(duration: 40, startPosition: -12)
        XCTAssertEqual(playlist.startPosition, 0)
        XCTAssertEqual(playlist.index(for: "vod-2.ts"), 2)
        for name in ["vod--1.ts", "vod-7.ts", "vod-02.ts", "vod-2.ts?source=private", "../vod-1.ts", "vod-999999999999999999999.ts"] {
            XCTAssertNil(playlist.index(for: name))
        }
        for duration in [0.0, -1, .nan, .infinity, 86_401] {
            XCTAssertThrowsError(try CarPlayVODPlaylist(duration: duration))
        }
        XCTAssertThrowsError(try CarPlayVODPlaylist(duration: 40, startPosition: .infinity))
        XCTAssertEqual(try CarPlayVODPlaylist(duration: 40, startPosition: 50).startPosition, 39.999, accuracy: 0.001)
    }

    func testSystemCarPlayDoesNotLoseVideoWhenASceneIsPresent() {
        let policy = VideoOutputPolicy(video: true, phone: false, carPlay: true, supportsVideo: true,
            externalDisplay: true, externalTV: false, cast: false)
        XCTAssertTrue(policy.systemCarPlay)
        XCTAssertTrue(policy.allowsExternalPlayback)
        XCTAssertFalse(policy.ownedDisplay)
        let tv = VideoOutputPolicy(video: true, phone: false, carPlay: true, supportsVideo: true,
            externalDisplay: true, externalTV: true, cast: false)
        XCTAssertTrue(tv.ownedDisplay)
        XCTAssertFalse(tv.allowsExternalPlayback)
        let phone = VideoOutputPolicy(video: true, phone: true, carPlay: true, supportsVideo: true,
            externalDisplay: false, externalTV: false, cast: false)
        XCTAssertFalse(phone.allowsExternalPlayback)
        XCTAssertFalse(phone.systemCarPlay)
    }

    func testOnlyKnownProviderRoutesCanOfferAnHLSProbe() throws {
        let original = try XCTUnwrap(URL(string: "https://provider.example/base/movie/u%2B1/p%40ss/123.mkv?token=a%2Bb"))
        XCTAssertEqual(CarPlayMediaSource.hlsCandidate(for: original)?.absoluteString,
                       "https://provider.example/base/movie/u%2B1/p%40ss/123.m3u8?token=a%2Bb")
        for value in ["https://example.com/film.mkv", "https://example.com/movie/u/p/title.mkv", "file:///movie/u/p/123.mkv",
                      "https://example.com/movie/u/p/123.mp4", "https://example.com/archive/movie/u/123.ts"] {
            XCTAssertNil(CarPlayMediaSource.hlsCandidate(for: URL(string: value)!))
        }
        XCTAssertFalse(CarPlayMediaSource.isHLS(Data("#EXTM3U\n#EXTINF:-1,Channel\nhttps://example.com/live.ts".utf8)))
        XCTAssertFalse(CarPlayMediaSource.isHLS(Data("<html>not found</html>".utf8)))
    }

    func testRelayRewritesRenditionsKeysMapsAndSegmentsWithoutLosingRanges() throws {
        let body = Data("""
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-KEY:METHOD=AES-128,URI="../keys/key?token=secret"
        #EXT-X-MAP:URI="init.mp4",BYTERANGE="128@0"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="audio/playlist.m3u8"
        #EXT-X-BYTERANGE:200@128
        #EXTINF:4,
        chunks/movie.m4s?token=secret
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://content-key"
        """.utf8)
        var sources: [URL] = []
        let output = try HLSRelayPlaylist.rewrite(body, relativeTo: URL(string: "https://cdn.example/redirected/master.m3u8")!) { url in
            sources.append(url)
            return URL(string: "http://127.0.0.1/session/\(sources.count)")!
        }
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertEqual(sources.map(\.absoluteString), ["https://cdn.example/keys/key?token=secret", "https://cdn.example/redirected/init.mp4",
            "https://cdn.example/redirected/audio/playlist.m3u8", "https://cdn.example/redirected/chunks/movie.m4s?token=secret"])
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("BYTERANGE=\"128@0\""))
        XCTAssertTrue(text.contains("#EXT-X-BYTERANGE:200@128"))
        XCTAssertTrue(text.contains("skd://content-key"))
    }

    func testUnderlyingAccessFailureIsRecognizedWithoutExportingURLs() throws {
        let cause = NSError(domain: NSURLErrorDomain, code: -1102, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://secret.example/password"])
        let failure = DiagnosticFailure(NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: cause]))
        XCTAssertTrue(failure.contains(family: .url, code: -1102))
        let data = try JSONEncoder().encode(failure)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
        let legacy = try JSONDecoder().decode(DiagnosticFailure.self, from: Data(#"{"family":"url","code":-1102}"#.utf8))
        XCTAssertTrue(legacy.contains(family: .url, code: -1102))
    }

    func testManifestBOMAndWindowsLineEndingsDoNotBecomeResourceURLs() throws {
        let body = Data("\u{feff}#EXTM3U\r\n#EXT-X-TARGETDURATION:2\r\n#EXTINF:2,\r\npart.ts\r\n".utf8)
        var resources: [URL] = []
        let output = try HLSRelayPlaylist.rewrite(body, relativeTo: URL(string: "https://example.com/list.m3u8")!) { url in
            resources.append(url)
            return URL(string: "http://127.0.0.1/part")!
        }
        XCTAssertEqual(resources.map(\.absoluteString), ["https://example.com/part.ts"])
        XCTAssertTrue(String(decoding: output, as: UTF8.self).hasPrefix("#EXTM3U\n#EXT-X-TARGETDURATION:2\n"))
    }
}
