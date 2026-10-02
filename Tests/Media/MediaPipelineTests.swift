import XCTest
import AVFoundation
import CoreVideo
import MirrorCore
@testable import MirrorMedia

final class MediaPipelineTests: XCTestCase {
    func testCapturedAudioAndVideoDecodeOnOneTimeline() async throws {
        let buffer = HLSBuffer()
        let encoder = ScreenStreamEncoder(buffer: buffer)
        defer { encoder.stop() }
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        encoder.submit(try XCTUnwrap(pixel), presentationTime: .zero)
        encoder.start()
        let began = ProcessInfo.processInfo.systemUptime
        var frames: Int64 = 0
        while ProcessInfo.processInfo.systemUptime - began < 4.5 {
            // Stay slightly ahead of the real-time writer, like ReplayKit's PCM batches.
            let desired = Int64((ProcessInfo.processInfo.systemUptime - began + 0.1) * 48_000)
            while frames < desired {
                let samples = (0..<1024).flatMap { index -> [Float] in
                    let value = Float(sin(Double(frames + Int64(index)) * 2 * .pi * 440 / 48_000) * 0.4)
                    return [value, value]
                }
                encoder.submitAudio(try XCTUnwrap(PCMUtilities.sample(samples: samples, at: frames)))
                frames += 1024
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(encoder.snapshot().failure)
        XCTAssertGreaterThan(encoder.snapshot().receivedAudioFrames, 48_000)
        XCTAssertGreaterThan(encoder.snapshot().encodedAudioFrames, 48_000)
        let snapshot = buffer.snapshot()
        var data = try XCTUnwrap(snapshot.initialization)
        snapshot.segments.forEach { data.append($0.data) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try XCTUnwrap(audioTracks.first), video = try XCTUnwrap(videoTracks.first)
        let audioRange = try await audio.load(.timeRange), videoRange = try await video.load(.timeRange)
        print("AV_TIMELINE", audioRange.start.seconds, audioRange.duration.seconds, videoRange.start.seconds, videoRange.duration.seconds)
        XCTAssertLessThan(abs(audioRange.start.seconds - videoRange.start.seconds), 0.15)
        XCTAssertLessThan(abs(audioRange.duration.seconds - videoRange.duration.seconds), 0.2)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer(), let pcm = PCMUtilities.copyPCM(sample), let channel = pcm.floatChannelData?[0] {
            for index in 0..<Int(pcm.frameLength) { peak = max(peak, abs(channel[index])) }
        }
        XCTAssertGreaterThan(peak, 0.1, "AAC must contain the source tone, not only a silent audio track")
        XCTAssertEqual(reader.status, .completed)
    }

    func testRepeatedStopsRevokeAllMedia() async throws {
        for _ in 0..<10 {
            let buffer = HLSBuffer()
            let encoder = ScreenStreamEncoder(buffer: buffer)
            encoder.start(); encoder.stop(); encoder.stop()
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(buffer.snapshot().byteCount, 0)
            XCTAssertFalse(buffer.setInitialization(Data([1, 2])))
        }
    }

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
