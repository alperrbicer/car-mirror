import XCTest
import Network
import MirrorCore
@testable import MirrorMedia

final class MediaRelayTests: XCTestCase {
    func testRelaysManifestRedirectCookiesAndRangesAndRevokesOnStop() async throws {
        let fixture = try RelayFixture { path, headers in
            if path == "/start.m3u8" {
                return (302, ["Location": "/media/list.m3u8", "Set-Cookie": "access=yes; Path=/"], Data())
            }
            if path == "/media/list.m3u8" {
                return (200, ["Content-Type": "application/vnd.apple.mpegurl"], Data("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nvideo.ts?token=private\n#EXT-X-ENDLIST\n".utf8))
            }
            if path == "/media/video.ts?token=private", headers.lowercased().contains("cookie: access=yes"), headers.contains("bytes=2-5") {
                return (206, ["Content-Type": "video/mp2t", "Content-Range": "bytes 2-5/8", "Accept-Ranges": "bytes"], Data([2, 3, 4, 5]))
            }
            return (403, [:], Data())
        }
        defer { fixture.stop() }
        let origin = try await fixture.start()
        let relay = try MediaRelayServer(source: origin.appendingPathComponent("start.m3u8"))
        defer { relay.stop() }
        let address = try await start(relay)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (manifest, response) = try await session.data(from: address)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let text = String(decoding: manifest, as: UTF8.self)
        XCTAssertFalse(text.contains("private"))
        let segment = try XCTUnwrap(text.components(separatedBy: .newlines).first { $0.hasPrefix("http://") }.flatMap(URL.init(string:)))
        var request = URLRequest(url: segment)
        request.setValue("bytes=2-5", forHTTPHeaderField: "Range")
        let (bytes, segmentResponse) = try await session.data(for: request)
        XCTAssertEqual(bytes, Data([2, 3, 4, 5]))
        XCTAssertEqual((segmentResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual((segmentResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"), "bytes 2-5/8")
        let unknown = address.deletingLastPathComponent().appendingPathComponent("unregistered.ts")
        let (_, denied) = try await session.data(from: unknown)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404)
        relay.stop()
        do { _ = try await session.data(from: address); XCTFail("Stopped relay must revoke its URLs") } catch { }
    }

    func testLargeProgressiveBodyAndHEADRemainBoundedAndByteExact() async throws {
        let payload = Data((0..<524_288).map { UInt8($0 % 251) })
        let fixture = try RelayFixture { _, _ in (200, ["Content-Type": "video/mp4", "Accept-Ranges": "bytes"], payload) }
        defer { fixture.stop() }
        let origin = try await fixture.start()
        let relay = try MediaRelayServer(source: origin.appendingPathComponent("movie.mp4"))
        defer { relay.stop() }
        let url = try await start(relay)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "HEAD"
        let (head, response) = try await session.data(for: request)
        XCTAssertTrue(head.isEmpty)
        XCTAssertEqual(response.expectedContentLength, Int64(payload.count))
        let (bytes, getResponse) = try await session.data(from: url)
        XCTAssertEqual((getResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, payload)
    }

    func testProviderAlternativeMustActuallyBeHLS() async throws {
        let fixture = try RelayFixture { path, _ in
            if path == "/series/u/p/123.m3u8" {
                return (200, ["Content-Type": "application/vnd.apple.mpegurl"], Data("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\npart.ts\n#EXT-X-ENDLIST\n".utf8))
            }
            return (200, ["Content-Type": "video/x-matroska"], Data(repeating: 0, count: 4096))
        }
        defer { fixture.stop() }
        let origin = try await fixture.start()
        let supported = try await CarPlayMediaResolver.nativeAlternative(for: origin.appendingPathComponent("series/u/p/123.mkv"))
        XCTAssertEqual(supported, origin.appendingPathComponent("series/u/p/123.m3u8"))
        let unsupported = try await CarPlayMediaResolver.nativeAlternative(for: origin.appendingPathComponent("movie/u/p/456.mkv"))
        XCTAssertNil(unsupported, "A renamed URL returning MKV is not an HLS rendition")
    }

    func testExtensionlessManifestIsRewrittenWhenHeaderArrivesInSeparateChunks() async throws {
        let fixture = try RelayFixture(fragmentPrefixBytes: 3) { _, _ in
            (200, ["Content-Type": "application/octet-stream"],
             Data("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nhttps://provider.example/part.ts?password=secret\n#EXT-X-ENDLIST\n".utf8))
        }
        defer { fixture.stop() }
        let origin = try await fixture.start()
        let relay = try MediaRelayServer(source: origin.appendingPathComponent("stream"))
        defer { relay.stop() }
        let url = try await start(relay)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (body, response) = try await session.data(from: url)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertEqual(response.mimeType, "application/vnd.apple.mpegurl")
        XCTAssertTrue(text.hasPrefix("#EXTM3U\n"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("http://127.0.0.1:"))
    }

    private func start(_ server: MediaRelayServer) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            server.start(host: "127.0.0.1", onReady: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
        }
    }
}

private final class RelayFixture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Mirivo.RelayFixture")
    private let listener: NWListener
    private let response: @Sendable (String, String) -> (Int, [String: String], Data)
    private var connections: [UUID: NWConnection] = [:]
    private let fragmentPrefixBytes: Int
    private var startCompleted = false
    init(fragmentPrefixBytes: Int = 0, response: @escaping @Sendable (String, String) -> (Int, [String: String], Data)) throws {
        self.fragmentPrefixBytes = fragmentPrefixBytes
        self.response = response
        listener = try NWListener(using: .tcp, on: .any)
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.startCompleted else { return }
                switch state {
                case .ready:
                    self.startCompleted = true
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)")!)
                case .failed(let error): self.startCompleted = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection
                connection.start(queue: self.queue)
                self.receive(id, data: Data())
            }
            listener.start(queue: queue)
        }
    }
    private func receive(_ id: UUID, data: Data) {
        connections[id]?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            guard let self else { return }
            var request = data; if let bytes { request.append(bytes) }
            if request.range(of: Data("\r\n\r\n".utf8)) == nil {
                if !complete && error == nil { self.receive(id, data: request) }
                else { self.connections.removeValue(forKey: id)?.cancel() }
                return
            }
            let text = String(decoding: request, as: UTF8.self)
            let first = text.components(separatedBy: "\r\n")[0].split(separator: " ")
            let (status, headers, body) = self.response(first.count > 1 ? String(first[1]) : "", text)
            let head = "HTTP/1.1 \(status) Status\r\nContent-Length: \(body.count)\r\nConnection: close\r\n" + headers.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
            if first.first != "HEAD", self.fragmentPrefixBytes > 0, body.count > self.fragmentPrefixBytes {
                self.connections[id]?.send(content: Data(head.utf8) + body.prefix(self.fragmentPrefixBytes), completion: .contentProcessed { _ in
                    self.queue.asyncAfter(deadline: .now() + .milliseconds(30)) {
                        self.connections[id]?.send(content: Data(body.dropFirst(self.fragmentPrefixBytes)), completion: .contentProcessed { _ in
                            self.connections.removeValue(forKey: id)?.cancel()
                        })
                    }
                })
            } else {
                self.connections[id]?.send(content: Data(head.utf8) + (first.first == "HEAD" ? Data() : body), completion: .contentProcessed { _ in
                    self.connections.removeValue(forKey: id)?.cancel()
                })
            }
        }
    }
    func stop() { queue.async { [self] in listener.cancel(); connections.values.forEach { $0.cancel() }; connections.removeAll() } }
}
