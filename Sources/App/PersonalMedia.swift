import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import UIKit

/// Only user-selected files enter this directory. URLs are never saved to the source library.
enum PersonalMediaFiles {
    static let directory: URL = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MirivoSharing", isDirectory: true)
        // Nothing in this directory is restored between launches; release the previous session's copies.
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    static func copy(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func remove(_ urls: [URL]) {
        for url in urls where url.deletingLastPathComponent().deletingLastPathComponent() == directory {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    static func outputURL() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Slideshow.mp4")
    }
}

struct PickedMediaFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { file in
            PickedMediaFile(url: try PersonalMediaFiles.copy(file.file))
        }
        FileRepresentation(importedContentType: .image) { file in
            PickedMediaFile(url: try PersonalMediaFiles.copy(file.file))
        }
    }
}

enum PersonalMediaError: Error { case unreadable, exportFailed }

/// Fullscreen playback, exporting and local casting can overlap without restoring the idle timer early.
@MainActor
enum MediaScreenAwake {
    private static var leases: Set<UUID> = []
    private static var previous = false
    static func acquire() -> UUID {
        if leases.isEmpty { previous = UIApplication.shared.isIdleTimerDisabled }
        let id = UUID(); leases.insert(id)
        UIApplication.shared.isIdleTimerDisabled = true
        return id
    }
    static func release(_ id: UUID?) {
        guard let id, leases.remove(id) != nil else { return }
        if leases.isEmpty { UIApplication.shared.isIdleTimerDisabled = previous }
    }
}

/// A local H.264 slideshow uses the same real player and TV route as videos.
/// Originals are untouched; slides are fitted (never cropped) to a 1080p canvas.
enum PhotoSlideshow {
    static let maximumPhotos = 20
    static let intervals = [3, 5, 8]

    static func thumbnail(_ url: URL, maxSize: Int = 480) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    static func export(_ photos: [URL], secondsPerPhoto: Int,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard !photos.isEmpty, photos.count <= maximumPhotos, intervals.contains(secondsPerPhoto) else {
            throw PersonalMediaError.unreadable
        }
        let task = Task.detached(priority: .userInitiated) {
            try await render(photos, secondsPerPhoto: secondsPerPhoto, progress: progress)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private static func render(_ photos: [URL], secondsPerPhoto: Int,
                               progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let output = try PersonalMediaFiles.outputURL()
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var completed = false
        defer {
            if !completed {
                writer.cancelWriting()
                PersonalMediaFiles.remove([output])
            }
        }
        let width = 1920, height = 1080, fps = 30
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000,
                                             AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw PersonalMediaError.exportFailed }
        writer.add(input)
        guard writer.startWriting() else { throw PersonalMediaError.exportFailed }
        writer.startSession(atSourceTime: .zero)
        let totalFrames = photos.count * secondsPerPhoto * fps
        var frame = 0
        for photo in photos {
            try Task.checkCancellation()
            guard let buffer = makeBuffer(photo, pool: adaptor.pixelBufferPool, width: width, height: height) else {
                throw PersonalMediaError.unreadable
            }
            for _ in 0..<(secondsPerPhoto * fps) {
                try Task.checkCancellation()
                let deadline = Date().addingTimeInterval(15)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else { throw PersonalMediaError.exportFailed }
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else {
                    throw PersonalMediaError.exportFailed
                }
                frame += 1
                if frame % fps == 0 { progress(Double(frame) / Double(totalFrames)) }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(totalFrames), timescale: Int32(fps)))
        input.markAsFinished()
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw PersonalMediaError.exportFailed }
        completed = true
        return output
    }

    private static func makeBuffer(_ photo: URL, pool: CVPixelBufferPool?, width: Int, height: Int) -> CVPixelBuffer? {
        autoreleasepool {
            guard let pool, let image = thumbnail(photo, maxSize: max(width, height)) else { return nil }
            var result: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result) == kCVReturnSuccess, let buffer = result else { return nil }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                                          width: size.width, height: size.height))
            return buffer
        }
    }
}
