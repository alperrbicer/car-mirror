import XCTest
@testable import MirrorCore

final class StreamCoreTests: XCTestCase {
    private func readyBuffer() -> HLSBuffer {
        let buffer = HLSBuffer()
        buffer.setInitialization(Data((0..<100).map(UInt8.init)))
        for _ in 0..<3 { buffer.append(Data([1, 2, 3]), duration: 1) }
        return buffer
    }

    private func request(_ path: String, method: String = "GET", headers: String = "") -> Data {
        Data("\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n\(headers)\r\n".utf8)
    }

    func testPlaylistWaitsForPlayableWindow() {
        let buffer = HLSBuffer()
        XCTAssertNil(buffer.playlist())
        buffer.setInitialization(Data([0]))
        buffer.append(Data([1]), duration: 1)
        buffer.append(Data([2]), duration: 1)
        XCTAssertNil(buffer.playlist())
        buffer.append(Data([3]), duration: 1)
        XCTAssertTrue(buffer.snapshot().isReady)
        XCTAssertTrue(String(decoding: buffer.playlist()!, as: UTF8.self).contains("#EXT-X-MAP:URI=\"init.mp4\""))
    }

    func testSlidingPlaylistSequenceAndRetention() {
        let buffer = HLSBuffer()
        buffer.setInitialization(Data([0]))
        for _ in 0..<20 { buffer.append(Data([1]), duration: 1.05) }
        let text = String(decoding: buffer.playlist()!, as: UTF8.self)
        XCTAssertTrue(text.contains("#EXT-X-MEDIA-SEQUENCE:14\n"))
        XCTAssertTrue(text.contains("#EXT-X-TARGETDURATION:2\n"))
        XCTAssertEqual(buffer.snapshot().segments.count, 10)
        XCTAssertNil(buffer.media(named: "segment-9.m4s"))
        XCTAssertNotNil(buffer.media(named: "segment-10.m4s"))
    }

    func testMemoryAndInvalidSegmentsAreBounded() {
        let buffer = HLSBuffer(maximumBytes: 1_200)
        XCTAssertTrue(buffer.setInitialization(Data(repeating: 0, count: 10)))
        for _ in 0..<30 { XCTAssertTrue(buffer.append(Data(repeating: 1, count: 350), duration: 1)) }
        XCTAssertLessThanOrEqual(buffer.snapshot().byteCount, 1_200)
        XCTAssertFalse(buffer.append(Data([1]), duration: .nan))
        XCTAssertFalse(buffer.append(Data([1]), duration: 4))
        XCTAssertFalse(buffer.append(Data(repeating: 1, count: 500), duration: 1))
    }

    func testStopRevokesMediaAndLateCallbacks() {
        let buffer = readyBuffer()
        buffer.invalidate()
        XCTAssertNil(buffer.playlist())
        XCTAssertNil(buffer.media(named: "init.mp4"))
        XCTAssertNil(buffer.media(named: "segment-1.m4s"))
        XCTAssertEqual(buffer.snapshot().byteCount, 0)
        XCTAssertFalse(buffer.setInitialization(Data([4])))
        XCTAssertFalse(buffer.append(Data([4]), duration: 1))
    }

    func testOnlySessionPathsCanReadScreenData() {
        let router = StreamHTTPRouter(token: "secret", buffer: readyBuffer())
        for path in ["/", "/wrong/init.mp4", "/secret/../init.mp4", "/secret/%2e%2e/init.mp4", "/secret/init.mp4?x=1"] {
            XCTAssertEqual(router.respond(to: request(path)).status, 404, path)
        }
        XCTAssertEqual(router.respond(to: request("/secret/stream.m3u8")).status, 200)
        XCTAssertEqual(router.respond(to: request("/secret/init.mp4", method: "POST")).status, 405)
    }

    func testPlayerByteRangesAndHeadRequests() {
        let router = StreamHTTPRouter(token: "secret", buffer: readyBuffer())
        let partial = router.respond(to: request("/secret/init.mp4", headers: "Range: bytes=10-19\r\n"))
        XCTAssertEqual(partial.status, 206)
        XCTAssertEqual(partial.body, Data((10..<20).map(UInt8.init)))
        XCTAssertEqual(partial.headers["Content-Range"], "bytes 10-19/100")
        let suffix = router.respond(to: request("/secret/init.mp4", headers: "Range: bytes=-5\r\n"))
        XCTAssertEqual(suffix.body, Data((95..<100).map(UInt8.init)))
        let head = router.respond(to: request("/secret/init.mp4", method: "HEAD"))
        XCTAssertEqual(head.headers["Content-Length"], "100")
        XCTAssertTrue(head.body.isEmpty)
        let beyond = router.respond(to: request("/secret/init.mp4", headers: "Range: bytes=200-\r\n"))
        XCTAssertEqual(beyond.status, 416)
        XCTAssertEqual(beyond.headers["Content-Range"], "bytes */100")
    }

    func testMalformedRequestsDoNotCrashOrReadData() {
        let router = StreamHTTPRouter(token: "secret", buffer: readyBuffer())
        XCTAssertEqual(router.respond(to: Data(repeating: 65, count: 9_000)).status, 400)
        XCTAssertEqual(router.respond(to: Data("GET\r\n\r\n".utf8)).status, 400)
        XCTAssertEqual(router.respond(to: request("/secret/init.mp4", headers: "Range: bytes=0-1,4-8\r\n")).status, 416)
        XCTAssertEqual(router.respond(to: request("/secret/init.mp4", headers: "Range: bytes=0-99999999999999999999999999\r\n")).status, 416)
    }

    func testHeartbeatCannotClaimAnOldSessionIsLive() {
        let now = Date(timeIntervalSince1970: 100)
        var status = CaptureStatus(phase: .live, updatedAt: now)
        status.segmentCount = 3
        status.loopbackURL = URL(string: "http://127.0.0.1:1234/token/stream.m3u8")
        XCTAssertTrue(status.canPlay(at: now))
        XCTAssertFalse(status.canPlay(at: now.addingTimeInterval(6)))
        status.phase = .paused
        XCTAssertFalse(status.canPlay(at: now))
        status.phase = .stopped
        XCTAssertFalse(status.canPlay(at: now))
    }
}
