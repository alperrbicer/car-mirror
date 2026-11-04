import XCTest
@testable import MirrorCore

final class CarPlayMediaPolicyTests: XCTestCase {
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
