import XCTest
import AVFoundation
import CoreVideo
import MirrorCore
@testable import MirrorMedia

final class MediaPipelineTests: XCTestCase {
    func testVehicleProbeContainsChangingDecodableFrames() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let asset = AVURLAsset(url: root.appendingPathComponent("Resources/ConnectionProbe.mp4"))
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 14)
        let generator = AVAssetImageGenerator(asset: asset)
        let first = try await generator.image(at: .zero).image
        let second = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 30)).image
        XCTAssertEqual(first.width, 960)
        XCTAssertEqual(first.height, 540)
        XCTAssertNotEqual(first.dataProvider?.data as Data?, second.dataProvider?.data as Data?, "Vehicle probe must visibly advance")
    }

    func testStaticScreenProducesDecodableLiveHLSAndStopsCleanly() async throws {
        let buffer = HLSBuffer()
        let encoder = ScreenStreamEncoder(buffer: buffer)
        defer { encoder.stop() }
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer), kCVReturnSuccess)
        let frame = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(frame, [])
        let bytes = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(frame)
        for y in 0..<90 {
            for x in 0..<160 {
                let offset = y * stride + x * 4
                bytes[offset] = 25; bytes[offset + 1] = 200
                bytes[offset + 2] = 50; bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        // Only one input frame: the clock must keep a static screen's playlist advancing.
        encoder.submit(frame, orientation: .right)
        encoder.start()
        for _ in 0..<70 {
            if buffer.snapshot().isReady || encoder.snapshot().failure != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let snapshot = buffer.snapshot()
        XCTAssertNil(encoder.snapshot().failure)
        XCTAssertTrue(snapshot.isReady, "No playable HLS window was emitted")
        XCTAssertGreaterThan(encoder.snapshot().encoded, 20)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("probe.mp4")
        var movie = try XCTUnwrap(snapshot.initialization)
        snapshot.segments.forEach { movie.append($0.data) }
        try movie.write(to: file)
        let asset = AVURLAsset(url: file)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 960)
        XCTAssertEqual(size.height, 540)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let decoded = try XCTUnwrap(output.copyNextSampleBuffer())
        let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(decoded))
        CVPixelBufferLockBaseAddress(image, .readOnly)
        let result = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(image)
        XCTAssertGreaterThan(result[270 * row + 480 * 4 + 1], 150, "Center should contain the source image")
        XCTAssertLessThan(result[270 * row + 5 * 4 + 1], 25, "Portrait content must have black side bars")
        CVPixelBufferUnlockBaseAddress(image, .readOnly)
        reader.cancelReading()
        encoder.stop()
        XCTAssertEqual(buffer.snapshot().byteCount, 0)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(buffer.playlist(), "Late callbacks must not restore a stopped session")
    }

    func testHTTPServerServesOnlyTokenProtectedLocalMedia() async throws {
        let buffer = HLSBuffer()
        buffer.setInitialization(Data([0, 1, 2, 3, 4]))
        for _ in 0..<3 { buffer.append(Data([8, 9]), duration: 1) }
        let server = LocalStreamServer(buffer: buffer)
        defer { buffer.invalidate(); server.stop() }
        let ready = expectation(description: "Listener ready")
        var port: UInt16?
        server.start(onReady: { value in port = value; ready.fulfill() }, onFailure: { error in
            XCTFail("Listener failed: \(error)"); ready.fulfill()
        })
        await fulfillment(of: [ready], timeout: 4)
        let base = server.url(host: "127.0.0.1", port: try XCTUnwrap(port))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: base)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix("#EXTM3U"))
        let denied = base.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("init.mp4")
        let (_, forbiddenResponse) = try await session.data(from: denied)
        XCTAssertEqual((forbiddenResponse as? HTTPURLResponse)?.statusCode, 404)
        var range = URLRequest(url: base.deletingLastPathComponent().appendingPathComponent("init.mp4"))
        range.setValue("bytes=1-3", forHTTPHeaderField: "Range")
        let (slice, slicedResponse) = try await session.data(for: range)
        XCTAssertEqual((slicedResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(slice, Data([1, 2, 3]))
        buffer.invalidate()
        let (_, stoppedResponse) = try await session.data(from: base)
        XCTAssertEqual((stoppedResponse as? HTTPURLResponse)?.statusCode, 503)
    }
}
