// Test-only live source. Compile with the real Core/Media files; see docs/VEHICLE_PLAYBACK_QA.md.
import Foundation
import AVFoundation
import CoreVideo

@main
struct VehicleScreenFixture {
    static func main() async throws {
        let buffer = HLSBuffer(retainedSegments: 24, playlistSegments: 12, targetDuration: 1)
        let encoder = ScreenStreamEncoder(buffer: buffer, quality: .high, includesAudio: true, segmentInterval: 0.5)
        let server = LocalStreamServer(buffer: buffer)
        let started = Date().timeIntervalSince1970
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            server.start(onReady: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
        }
        try JSONSerialization.data(withJSONObject: ["url": server.localStreamURL(port: port).absoluteString, "started": started])
            .write(to: URL(fileURLWithPath: "build/vehicle-stream-probe.json"))
        encoder.start()
        var audioFrames: Int64 = 0
        for index in 0..<36_000 {
            let elapsed = Date().timeIntervalSince1970 - started
            let ticks = Int(elapsed * 10)
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
            if let pixel {
                CVPixelBufferLockBaseAddress(pixel, [])
                let bytes = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(pixel)
                for y in 0..<360 { for x in 0..<640 {
                    let n = y * stride + x * 4
                    bytes[n] = UInt8((x + index * 3) % 200)
                    bytes[n+1] = UInt8(100 + (index % 100))
                    bytes[n+2] = UInt8((y + index * 2) % 200)
                    bytes[n+3] = 255
                    if y >= 140 && y < 220 && x >= 80 && x < 560 {
                        let bit = (x - 80) / 20
                        let value: UInt8 = ticks & (1 << bit) == 0 ? 16 : 240
                        bytes[n] = value; bytes[n+1] = value; bytes[n+2] = value
                    }
                }}
                CVPixelBufferUnlockBaseAddress(pixel, [])
                encoder.submit(pixel, presentationTime: CMTime(seconds: elapsed, preferredTimescale: 48_000))
                let desired = Int64((elapsed + 0.1) * 48_000)
                while audioFrames < desired {
                    let samples = (0..<1024).flatMap { n -> [Float] in
                        let v = Float(sin(Double(audioFrames + Int64(n)) * 2 * .pi * 440 / 48_000) * 0.1)
                        return [v,v]
                    }
                    if let sample = PCMUtilities.sample(samples: samples, at: audioFrames) { encoder.submitAudio(sample) }
                    audioFrames += 1024
                }
            }
            if let failure = encoder.snapshot().failure { throw NSError(domain: "VehicleFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            try await Task.sleep(for: .milliseconds(33))
        }
        encoder.stop(); server.stop()
    }
}
