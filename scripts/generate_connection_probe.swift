#!/usr/bin/env swift
import Foundation
import AVFoundation
import CoreGraphics
import CoreText

// An original, silent reference clip isolates vehicle output from ReplayKit and LAN transport.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/ConnectionProbe.mp4")
try? FileManager.default.removeItem(at: destination)
let width = 960, height = 540, rate = 30, seconds = 15
let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_000_000, AVVideoMaxKeyFrameIntervalKey: rate]
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)

func text(_ string: String, size: CGFloat, y: CGFloat, context: CGContext) {
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    let attributed = NSAttributedString(string: string, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.96, alpha: 1)
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: (CGFloat(width) - CTLineGetTypographicBounds(line, nil, nil, nil)) / 2, y: y)
    CTLineDraw(line, context)
}

for frameIndex in 0..<(rate * seconds) {
    while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else { throw writer.error! }
        Thread.sleep(forTimeInterval: 0.002)
    }
    try autoreleasepool {
        var pixelBuffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw CocoaError(.coderInvalidValue) }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(CGColor(red: 0.035, green: 0.05, blue: 0.07, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        text("Mirivo", size: 24, y: 432, context: context)
        text(String(format: "%02d:%02d.%02d", frameIndex / rate / 60, frameIndex / rate % 60, frameIndex % rate),
             size: 94, y: 260, context: context)
        text("DISPLAY TEST", size: 18, y: 196, context: context)
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(1,1,1), (1,1,0), (0,1,1), (0,1,0), (1,0,1), (1,0,0), (0,0,1)]
        for (index, color) in colors.enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fill(CGRect(x: 200 + index * 80, y: 145, width: 80, height: 20))
        }
        context.setFillColor(CGColor(red: 0.35, green: 0.91, blue: 0.77, alpha: 1))
        context.fillEllipse(in: CGRect(x: 30 + Double(frameIndex % 90) / 90 * 880, y: 55, width: 20, height: 20))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frameIndex), timescale: Int32(rate))) else {
            throw writer.error!
        }
    }
}
input.markAsFinished()
let completed = DispatchSemaphore(value: 0)
writer.finishWriting { completed.signal() }
completed.wait()
guard writer.status == .completed else { throw writer.error! }
print("Created 15-second 960x540 / 30 fps vehicle-output reference: \(destination.path)")
