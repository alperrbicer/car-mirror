import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import MirrorCore
#endif

/// Fixed-size, video-only H.264 → fragmented MP4. Keeps just the most recent input
/// frame and repeats it at 20 fps, including when the source screen is static.
/// Source-app audio continues on its own system route; we never recapture playback.
public final class ScreenStreamEncoder: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    public struct Statistics: Sendable {
        public var received = 0
        public var encoded = 0
        public var dropped = 0
        public var failure: String?
    }

    public static let width = 960
    public static let height = 540
    private let queue = DispatchQueue(label: "CarMirror.Encode", qos: .userInitiated)
    private let lock = NSLock()
    private let buffer: HLSBuffer
    private var latestFrame: CVPixelBuffer?
    private var orientation: CGImagePropertyOrientation = .up
    private var statistics = Statistics()
    private var accepting = true
    private var timer: DispatchSourceTimer?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var origin: TimeInterval?
    private var lastTime = CMTime.invalid
    // Broadcast extensions can run while the device disallows background GPU work.
    private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    public init(buffer: HLSBuffer) { self.buffer = buffer }

    public func start() {
        queue.async { [self] in
            guard timer == nil, isAccepting else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(4))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    public func submit(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        latestFrame = pixelBuffer
        self.orientation = orientation
        statistics.received += 1
    }

    public func snapshot() -> Statistics {
        lock.lock(); defer { lock.unlock() }
        return statistics
    }

    private var isAccepting: Bool {
        lock.lock(); defer { lock.unlock() }
        return accepting
    }

    public func stop() {
        lock.lock()
        accepting = false
        latestFrame = nil
        lock.unlock()
        buffer.invalidate()
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            // AVAssetWriter's delegate is immutable once writing starts. Revoke the
            // buffer above, then cancel; late delegate calls will be rejected.
            writer?.cancelWriting()
            writer = nil
            input = nil
            adaptor = nil
            context.clearCaches()
        }
    }

    private func tick() {
        lock.lock()
        let frame = accepting ? latestFrame : nil
        let orientation = orientation
        lock.unlock()
        guard let frame else { return }
        autoreleasepool {
            do {
                if writer == nil { try configure() }
                guard let writer, let input, let adaptor else { return }
                if writer.status == .failed { throw writer.error ?? failure("Video kodlayıcı durdu.") }
                guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else {
                    recordDrop(); return
                }
                var output: CVPixelBuffer?
                let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
                    [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary, &output)
                guard result == kCVReturnSuccess, let output else { recordDrop(); return }

                let bounds = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
                let source = CIImage(cvPixelBuffer: frame).oriented(orientation)
                let extent = source.extent
                let scale = min(bounds.width / extent.width, bounds.height / extent.height)
                let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                let fitted = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: (bounds.width - extent.width * scale) / 2,
                                                      y: (bounds.height - extent.height * scale) / 2))
                let image = fitted.composited(over: CIImage(color: .black).cropped(to: bounds))
                context.render(image, to: output, bounds: bounds, colorSpace: colorSpace)

                let now = ProcessInfo.processInfo.systemUptime
                if origin == nil { origin = now }
                let time = CMTime(seconds: now - origin!, preferredTimescale: 600)
                guard !lastTime.isValid || time > lastTime else { return }
                guard adaptor.append(output, withPresentationTime: time) else {
                    throw writer.error ?? failure("Görüntü karesi kodlanamadı.")
                }
                lastTime = time
                lock.lock(); statistics.encoded += 1; lock.unlock()
            } catch {
                lock.lock(); statistics.failure = error.localizedDescription; lock.unlock()
                stop()
            }
        }
    }

    private func configure() throws {
        let writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        writer.initialSegmentStartTime = .zero
        writer.delegate = self
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width, AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_800_000,
                AVVideoMaxKeyFrameIntervalKey: 20,
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
                AVVideoExpectedSourceFrameRateKey: 20,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw failure("H.264 kodlayıcı kullanılamıyor.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Video yayını başlatılamadı.") }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    public func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
                            segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        // Copy out of AVFoundation's delegate-owned backing store to bound its lifetime.
        let data = segmentData.withUnsafeBytes { Data($0) }
        let accepted: Bool
        switch segmentType {
        case .initialization:
            accepted = buffer.setInitialization(data)
        case .separable:
            let duration = segmentReport?.trackReports.first { $0.mediaType == .video }?.duration.seconds ?? .nan
            accepted = buffer.append(data, duration: duration)
        @unknown default: return
        }
        if !accepted && isAccepting {
            lock.lock(); statistics.failure = "Yayın tamponu veya bölüm süresi sınırı aşıldı. Yayını yeniden başlat."; lock.unlock()
            stop()
        }
    }

    private func recordDrop() {
        lock.lock(); statistics.dropped += 1; lock.unlock()
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "CarMirror.Encoder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
