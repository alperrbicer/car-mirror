import XCTest
@testable import MirrorCore

final class ProductTests: XCTestCase {
    func testSalesDisabledNeverLimitsFeatures() {
        let access = ProductAccess(salesEnabled: false, verifiedPro: false)
        XCTAssertTrue(access.fullAccess)
        XCTAssertNil(access.broadcastLimit)
        XCTAssertTrue(access.canAddSource(count: 900))
    }
    func testFreeAndVerifiedProHaveConsistentLimits() {
        let free = ProductAccess(salesEnabled: true, verifiedPro: false)
        XCTAssertTrue(free.canAddSource(count: 0))
        XCTAssertFalse(free.canAddSource(count: 1))
        XCTAssertEqual(free.broadcastLimit, 600)
        let pro = ProductAccess(salesEnabled: true, verifiedPro: true)
        XCTAssertTrue(pro.canAddSource(count: 50))
        XCTAssertNil(pro.broadcastLimit)
    }
    func testAudioTimelineFillsGapsAndNeverReplaysExpiredAudio() {
        var timeline = AudioTimeline()
        timeline.append(samples: [1, 1, 0.5, 0.5], at: 2)
        XCTAssertEqual(timeline.render(frameCount: 5), [0, 0, 0, 0, 1, 1, 0.5, 0.5, 0, 0])
        timeline.append(samples: [1, 1], at: 0)
        XCTAssertEqual(timeline.render(frameCount: 1), [0, 0])
        XCTAssertEqual(timeline.droppedFrames, 1)
    }
    func testAudioTimelineClipsPreOriginSamplesAndBoundsMemory() {
        var timeline = AudioTimeline()
        timeline.append(samples: [1, 1, 0.5, 0.5, 0.25, 0.25], at: -1)
        XCTAssertEqual(timeline.render(frameCount: 2), [0.5, 0.5, 0.25, 0.25])
        for i in 0..<200 { timeline.append(samples: Array(repeating: 1, count: 2048), at: Int64(2 + i * 1024)) }
        XCTAssertLessThanOrEqual(timeline.bufferedFrames, 96_000)
        XCTAssertGreaterThan(timeline.droppedFrames, 0)
    }
    func testM3UHandlesQuotedCommasGroupsRelativeAndDuplicateURLs() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="News, Live",Channel One
        streams/one.m3u8
        #EXTINF:-1,Duplicate
        streams/one.m3u8
        #EXTINF:-1,Channel Two
        #EXTGRP:Music
        https://media.example/two.m3u8
        #EXTINF:-1,Bad
        file:///etc/passwd
        """
        let channels = try M3UParser.parse(Data(text.utf8), baseURL: URL(string: "https://media.example/list.m3u")!, fallbackTitle: "List")
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].title, "Channel One")
        XCTAssertEqual(channels[0].group, "News, Live")
        XCTAssertEqual(channels[0].url.absoluteString, "https://media.example/streams/one.m3u8")
        XCTAssertEqual(channels[1].group, "Music")
    }
    func testHLSIsAChannelNotItsSegmentsAndInvalidSourcesAreRejected() throws {
        let url = URL(string: "https://media.example/live.m3u8")!
        let channels = try M3UParser.parse(Data("#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\n1.ts".utf8), baseURL: url, fallbackTitle: "Live")
        XCTAssertEqual(channels.map(\.url), [url])
        for invalid in ["file:///private/a", "javascript:alert(1)", "https://user:password@example.com/a", "https://example.com/a\nHeader: value"] {
            XCTAssertThrowsError(try MediaURL.validate(invalid))
        }
        XCTAssertThrowsError(try M3UParser.parse(Data("<html>login</html>".utf8), baseURL: url, fallbackTitle: "Invalid"))
        XCTAssertThrowsError(try M3UParser.parse(Data(repeating: 65, count: M3UParser.maximumBytes + 1), baseURL: url, fallbackTitle: "Large"))
    }
    func testXtreamCredentialsCannotInjectQueryParameters() throws {
        let secret = SourceSecret(url: URL(string: "https://server.example:8080")!, username: "a&password=other", password: "s+e?c/ret")
        let url = try XtreamEndpoint.playlist(secret: secret)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/get.php")
        XCTAssertEqual(components.queryItems?.first { $0.name == "username" }?.value, secret.username)
        XCTAssertEqual(components.queryItems?.filter { $0.name == "password" }.count, 1)
        XCTAssertEqual(components.queryItems?.first { $0.name == "password" }?.value, secret.password)
    }
}
