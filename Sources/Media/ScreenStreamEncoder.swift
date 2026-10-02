import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import MirrorCore
#endif

/// H.264 + AAC fragmented MP4, with a bounded PCM timeline shared by both tracks.
/// A single retained screen frame keeps static screens live without an input backlog.
public final class ScreenStreamEncoder: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    public struct Statistics: Sendable {
        public var received = 0
        public var encoded = 0
        public var dropped = 0
        public var receivedAudioFrames = 0
        public var encodedAudioFrames = 0
        public var droppedAudioFrames = 0
        public var failure: String?
    }

    public static let width = 960
    public static let height = 540
    private let queue = DispatchQueue(label: "CarMirror.Encode", qos: .userInitiated)
    private let lock = NSLock()
    private let buffer: HLSBuffer
    private var latestFrame: CVPixelBuffer?
    private var firstSourceTime: CMTime?
    private var firstHostTime: TimeInterval?
    private let quality: StreamQuality
    private let includesAudio: Bool
    private var audioInput: AVAssetWriterInput?
    private var audioConverter: AVAudioConverter?
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true)!
    private var audioTimeline = AudioTimeline()
    private var queuedAudio = 0
    private var caption: String = ""
    private var captionUpdatedAt: TimeInterval = 0
    private let captionRenderer = CaptionRenderer()
    private var orientation: CGImagePropertyOrientation = .up
    private var statistics = Statistics()
    private var accepting = true
    private var timer: DispatchSourceTimer?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var lastTime = CMTime.invalid
    // Broadcast extensions can run while the device disallows background GPU work.
    private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    public init(buffer: HLSBuffer, quality: StreamQuality = .balanced, includesAudio: Bool = true) {
        self.buffer = buffer
        self.quality = quality
        self.includesAudio = includesAudio
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil, isAccepting else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / quality.framesPerSecond), leeway: .milliseconds(4))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    public func submit(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up, presentationTime: CMTime = .invalid) {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        if firstHostTime == nil {
            firstHostTime = ProcessInfo.processInfo.systemUptime
            firstSourceTime = presentationTime.isNumeric ? presentationTime : .zero
        }
        latestFrame = pixelBuffer
        self.orientation = orientation
        statistics.received += 1
    }


    public func submitAudio(_ sample: CMSampleBuffer) {
        lock.lock()
        guard accepting, includesAudio, firstSourceTime != nil, queuedAudio < 8 else {
            statistics.droppedAudioFrames += CMSampleBufferGetNumSamples(sample)
            lock.unlock(); return
        }
        queuedAudio += 1
        let sourceTime = firstSourceTime!
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); queuedAudio -= 1; lock.unlock() }
            guard isAccepting, let pcm = PCMUtilities.copyPCM(sample),
                  let converted = PCMUtilities.convert(pcm, to: audioFormat, converter: &audioConverter) else { return }
            let relative = CMSampleBufferGetPresentationTimeStamp(sample) - sourceTime
            guard relative.isNumeric, abs(relative.seconds) < 86_400,
                  let data = converted.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(converted.frameLength) * 2))
            audioTimeline.append(samples: samples, at: Int64((relative.seconds * 48_000).rounded()))
            lock.lock()
            statistics.receivedAudioFrames += Int(converted.frameLength)
            statistics.droppedAudioFrames = audioTimeline.droppedFrames
            lock.unlock()
        }
    }

    public func setCaption(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        caption = String(text.suffix(180))
        captionUpdatedAt = ProcessInfo.processInfo.systemUptime
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
            audioInput = nil
            audioConverter = nil
            audioTimeline = AudioTimeline()
            captionRenderer.clear()
            context.clearCaches()
        }
    }

    private func tick() {
        lock.lock()
        let frame = accepting ? latestFrame : nil
        let orientation = orientation
        let startedAt = firstHostTime
        let captionText = ProcessInfo.processInfo.systemUptime - captionUpdatedAt < 5 ? caption : ""
        lock.unlock()
        guard let frame, let startedAt else { return }
        autoreleasepool {
            do {
                if writer == nil { try configure() }
                guard let writer, let input, let adaptor else { return }
                if writer.status == .failed { throw writer.error ?? failure("Video kodlayıcı durdu.") }
                let now = ProcessInfo.processInfo.systemUptime
                let time = lastTime.isValid ? CMTime(seconds: now - startedAt, preferredTimescale: 48_000) : .zero
                try appendAudio(until: time)
                guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else {
                    recordDrop(); return
                }
                var output: CVPixelBuffer?
                let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
                    [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary, &output)
                guard result == kCVReturnSuccess, let output else { recordDrop(); return }

                let bounds = CGRect(x: 0, y: 0, width: quality.width, height: quality.height)
                let source = CIImage(cvPixelBuffer: frame).oriented(orientation)
                let extent = source.extent
                let scale = min(bounds.width / extent.width, bounds.height / extent.height)
                let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                let fitted = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: (bounds.width - extent.width * scale) / 2,
                                                      y: (bounds.height - extent.height * scale) / 2))
                var image = fitted.composited(over: CIImage(color: .black).cropped(to: bounds))
                if let overlay = captionRenderer.image(text: captionText, width: quality.width, height: quality.height) {
                    image = overlay.composited(over: image)
                }
                context.render(image, to: output, bounds: bounds, colorSpace: colorSpace)

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
            AVVideoWidthKey: quality.width, AVVideoHeightKey: quality.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitrate,
                AVVideoMaxKeyFrameIntervalKey: quality.framesPerSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
                AVVideoExpectedSourceFrameRateKey: quality.framesPerSecond,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: quality.width,
            kCVPixelBufferHeightKey as String: quality.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw failure("H.264 kodlayıcı kullanılamıyor.") }
        writer.add(input)
        if includesAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
            ])
            audio.expectsMediaDataInRealTime = true
            guard writer.canAdd(audio) else { throw failure("Ses kodlayıcı kullanılamıyor.") }
            writer.add(audio)
            self.audioInput = audio
        }
        guard writer.startWriting() else { throw writer.error ?? failure("Video yayını başlatılamadı.") }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    private func appendAudio(until time: CMTime) throws {
        guard let audioInput else { return }
        let desired = Int64(time.seconds * 48_000)
        // Each tick does bounded work; a stalled encoder fails rather than filling
        // a long gap with a large allocation or silently drifting the audio clock.
        guard desired - audioTimeline.consumed < 96_000 else { throw failure("Ses aktarımı kesildi. Yayını yeniden başlat.") }
        while audioTimeline.consumed + 1024 <= desired, audioInput.isReadyForMoreMediaData {
            let start = audioTimeline.consumed
            let samples = audioTimeline.render(frameCount: 1024)
            guard let sample = PCMUtilities.sample(samples: samples, at: start), audioInput.append(sample) else {
                throw writer?.error ?? failure("Ses kodlanamadı.")
            }
            lock.lock(); statistics.encodedAudioFrames += 1024; lock.unlock()
        }
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
