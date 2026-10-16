import XCTest
import AVFoundation
import MirrorCore
@testable import MirrorMedia

final class LocalScreenStreamTests: XCTestCase {
    func testRotationReplacesCodecConfigurationAndKeepsEncoding() async throws {
        let buffer = HLSBuffer(retainedSegments: 24, playlistSegments: 12, targetDuration: 1)
        let encoder = ScreenStreamEncoder(buffer: buffer, includesAudio: false, segmentInterval: 0.5)
        defer { encoder.stop() }
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let frame = try XCTUnwrap(pixel)
        encoder.submit(frame, presentationTime: .zero)
        encoder.start()
        for _ in 0..<40 {
            if buffer.snapshot().isReady { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let initial = buffer.snapshot()
        XCTAssertTrue(initial.isReady)
        encoder.submit(frame, orientation: .right, presentationTime: CMTime(seconds: 2, preferredTimescale: 600))
        for _ in 0..<40 {
            let next = buffer.snapshot()
            if next.generation > initial.generation && next.isReady { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let rotated = buffer.snapshot()
        XCTAssertNil(encoder.snapshot().failure)
        XCTAssertEqual(rotated.generation, initial.generation + 1)
        XCTAssertTrue(rotated.isReady)
        XCTAssertNotEqual(rotated.initialization, initial.initialization)
        XCTAssertNil(buffer.media(named: "init.mp4"), "A receiver must not reuse codec configuration from before rotation")
        XCTAssertEqual(buffer.media(named: "init-1.mp4"), rotated.initialization)
        XCTAssertTrue(String(decoding: try XCTUnwrap(buffer.playlist()), as: UTF8.self).contains("init-1.mp4"))
        XCTAssertGreaterThan(rotated.segments.first?.sequence ?? -1, initial.segments.last?.sequence ?? -1)
    }

    func testLoopbackStartsAtLatestFragmentAndContinuesInOrder() async throws {
        let buffer = HLSBuffer()
        buffer.setInitialization(Data([10, 11]))
        for n in 0..<4 { buffer.append(Data([UInt8(n)]), duration: 1) }
        let server = LocalStreamServer(buffer: buffer)
        defer { buffer.invalidate(); server.stop() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            server.start(onReady: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: server.localStreamURL(port: port))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        buffer.append(Data([4]), duration: 1)
        buffer.append(Data([5]), duration: 1)
        var received = [UInt8]()
        for try await byte in bytes {
            received.append(byte)
            if received.count == 5 { break }
        }
        XCTAssertEqual(received, [10, 11, 3, 4, 5], "Do not replay the retained HLS backlog")
        let wrong = server.localStreamURL(port: port).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("live.mp4")
        let (_, denied) = try await session.data(from: wrong)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 404)
    }

    func testOutputDimensionsPreserveScreenAspectWithoutUpscaling() {
        let portrait = ScreenStreamEncoder.outputSize(source: CGSize(width: 1206, height: 2622), maximumEdge: 1280)
        XCTAssertEqual(portrait.height, 1280)
        XCTAssertEqual(Double(portrait.width) / Double(portrait.height), 1206.0 / 2622, accuracy: 0.003)
        let landscape = ScreenStreamEncoder.outputSize(source: CGSize(width: 2622, height: 1206), maximumEdge: 1280)
        XCTAssertEqual(landscape.width, portrait.height)
        XCTAssertEqual(landscape.height, portrait.width)
    }

    func testReaderWaitsForNewCodecAndFirstKeyframe() async throws {
        let buffer = HLSBuffer()
        let server = LocalStreamServer(buffer: buffer)
        defer { buffer.invalidate(); server.stop() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            server.start(onReady: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            buffer.setInitialization(Data([10, 11]))
            buffer.append(Data([12]), duration: 0.5)
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: server.localStreamURL(port: port))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        var received = [UInt8]()
        for try await byte in bytes {
            received.append(byte)
            if received.count == 3 { break }
        }
        XCTAssertEqual(received, [10, 11, 12])
    }
}
