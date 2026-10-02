import ReplayKit
import ImageIO

// Mutable state is confined to stateQueue; callbacks enter that queue before access.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "CarMirror.BroadcastState")
    private var store: BroadcastSessionStore?
    private var status = CaptureStatus()
    private var buffer: HLSBuffer?
    private var encoder: ScreenStreamEncoder?
    private var server: LocalStreamServer?
    private var heartbeat: DispatchSourceTimer?
    private let diagnostics = SessionDiagnostics(process: .broadcast)
    private var captionService: AnyObject?
    private var options = BroadcastOptions()
    private var broadcastBeganAt = Date()
    private var startTask: Task<Void, Never>?
    private var generation = UUID()
    private var recordedFirstFrame = false
    private var lastStatisticsAt = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        stateQueue.async { [self] in
            do {
                store = try BroadcastSessionStore()
                broadcastBeganAt = Date()
                prepareBroadcast()
            } catch { fail(error.localizedDescription, error: error) }
        }
    }

    override func broadcastPaused() {
        stateQueue.async { [self] in
            generation = UUID(); startTask?.cancel(); startTask = nil
            tearDown(stopHeartbeat: false)
            status.phase = .paused
            diagnostics.record(.capturePaused, sessionID: status.sessionID)
            publish()
        }
    }

    override func broadcastResumed() {
        stateQueue.async { [self] in
            if store?.shouldStop(sessionID: status.sessionID) == true { tick(); return }
            diagnostics.record(.captureResumed, sessionID: status.sessionID)
            prepareBroadcast()
        }
    }

    override func broadcastFinished() {
        stateQueue.sync {
            generation = UUID(); startTask?.cancel(); startTask = nil
            tearDown()
            if status.phase != .failed { status.phase = .stopped }
            diagnostics.record(.captureStopped, sessionID: status.sessionID)
            publish()
            diagnostics.flush()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        stateQueue.sync {
            guard let encoder else { return }
            switch sampleBufferType {
            case .video:
                guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
                let orientation = CGImagePropertyOrientation(rawValue: value?.uint32Value ?? 1) ?? .up
                if !recordedFirstFrame {
                    recordedFirstFrame = true
                    var values = DiagnosticValues()
                    values.width = CVPixelBufferGetWidth(image)
                    values.height = CVPixelBufferGetHeight(image)
                    diagnostics.record(.firstFrame, sessionID: status.sessionID, values: values)
                }
                encoder.submit(image, orientation: orientation, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            case .audioApp:
                encoder.submitAudio(sampleBuffer)
                if #available(iOS 26, *) { (captionService as? LiveCaptionTranscriber)?.append(sampleBuffer) }
            case .audioMic: break // Mirivo never requests or captures microphone audio.
            @unknown default: break
            }
        }
    }

    private func prepareBroadcast() {
        startTask?.cancel()
        let token = UUID()
        generation = token
        startTask = Task { [weak self] in
            let hasPro = SharedPreferences.salesEnabled ? await ProEntitlements.hasAccess() : false
            guard !Task.isCancelled else { return }
            self?.stateQueue.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.options = SharedPreferences.options()
                let access = ProductAccess(salesEnabled: SharedPreferences.salesEnabled, verifiedPro: hasPro)
                self.options.durationLimit = access.broadcastLimit
                if !access.fullAccess { self.options.captionsEnabled = false }
                do { try self.begin() } catch { self.fail(error.localizedDescription, error: error) }
            }
        }
    }

    private func begin() throws {
        tearDown()
        status = CaptureStatus()
        recordedFirstFrame = false
        lastStatisticsAt = .distantPast
        diagnostics.record(.captureStarted, sessionID: status.sessionID)
        try store?.write(status)
        let sessionID = status.sessionID
        let buffer = HLSBuffer()
        status.audioMode = options.audioMode
        let encoder = ScreenStreamEncoder(buffer: buffer, quality: options.quality, includesAudio: options.audioMode == .synchronized)
        if options.captionsEnabled, #available(iOS 26, *) {
            captionService = LiveCaptionTranscriber(locale: options.captionLocale,
                onText: { [weak encoder] text in encoder?.setCaption(text) }, onUnavailable: { [weak self] in
                    self?.stateQueue.async { [weak self] in
                        guard let self, self.status.sessionID == sessionID else { return }
                        self.status.captionsUnavailable = true
                    }
                })
        }
        let server = LocalStreamServer(buffer: buffer)
        self.buffer = buffer
        self.encoder = encoder
        self.server = server
        server.start(onReady: { [weak self, weak server] port in
            self?.stateQueue.async { [weak self, weak server] in
                guard let self, let server, self.status.sessionID == sessionID,
                      self.status.phase == .preparing else { return }
                self.status.loopbackURL = server.url(host: "127.0.0.1", port: port)
                if let address = LocalStreamServer.wifiAddress() {
                    self.status.networkURL = server.url(host: address, port: port)
                }
                self.publish()
            }
        }, onFailure: { [weak self] error in
            self?.stateQueue.async { [weak self] in
                guard self?.status.sessionID == sessionID else { return }
                self?.fail(L10n.tr("Araç için yayın bağlantısı kurulamadı."), error: error)
            }
        })
        encoder.start()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        heartbeat = timer
        timer.resume()
    }

    private func tick() {
        if let limit = options.durationLimit, Date().timeIntervalSince(broadcastBeganAt) >= limit {
            fail(L10n.tr("Ücretsiz paylaşım süresi doldu. Yeni bir yayın başlatabilir veya Pro’ya geçebilirsin.")); return
        }
        if store?.shouldStop(sessionID: status.sessionID) == true {
            tearDown()
            status.phase = .stopped
            var values = DiagnosticValues()
            values.reason = .user
            diagnostics.record(.captureStopped, sessionID: status.sessionID, values: values)
            publish()
            finishBroadcastWithError(NSError(domain: "CarMirror", code: 0,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("Ekran paylaşımı durduruldu.")]))
            return
        }
        if status.phase == .paused { publish(); return }
        guard let encoder, let buffer else { return }
        let stats = encoder.snapshot()
        if let failure = stats.failure { fail(failure); return }
        let contents = buffer.snapshot()
        status.receivedFrames = stats.received
        status.encodedFrames = stats.encoded
        status.droppedFrames = stats.dropped
        status.receivedAudioFrames = stats.receivedAudioFrames
        status.encodedAudioFrames = stats.encodedAudioFrames
        status.segmentCount = contents.totalSegments
        status.bufferedBytes = contents.byteCount
        if contents.isReady && status.loopbackURL != nil && status.phase != .live {
            status.phase = .live
            var values = DiagnosticValues()
            values.hasNetworkAddress = status.networkURL != nil
            diagnostics.record(.streamReady, sessionID: status.sessionID, values: values)
        }
        if Date().timeIntervalSince(lastStatisticsAt) >= 5 {
            lastStatisticsAt = Date()
            var values = DiagnosticValues()
            values.receivedFrames = stats.received
            values.encodedFrames = stats.encoded
            values.droppedFrames = stats.dropped
            values.receivedAudioFrames = stats.receivedAudioFrames
            values.encodedAudioFrames = stats.encodedAudioFrames
            values.droppedAudioFrames = stats.droppedAudioFrames
            values.segments = contents.totalSegments
            values.bufferedBytes = contents.byteCount
            values.thermalState = ProcessInfo.processInfo.thermalState.rawValue
            diagnostics.record(.streamStatistics, sessionID: status.sessionID, values: values)
        }
        publish()
    }

    private func publish() {
        status.updatedAt = Date()
        if [.stopped, .failed, .paused].contains(status.phase) {
            status.loopbackURL = nil
            status.networkURL = nil
            status.bufferedBytes = 0
        }
        do { try store?.write(status) }
        catch {
            var values = DiagnosticValues()
            values.reason = .storage
            values.failure = DiagnosticFailure(error)
            diagnostics.record(.failure, sessionID: status.sessionID, values: values)
            diagnostics.flush()
            tearDown()
            finishBroadcastWithError(error)
        }
    }

    private func fail(_ message: String, error: Error? = nil) {
        tearDown()
        status.phase = .failed
        status.message = message
        var values = DiagnosticValues()
        values.reason = .capture
        values.failure = error.map(DiagnosticFailure.init)
        status.failure = values.failure
        diagnostics.record(.failure, sessionID: status.sessionID, values: values)
        publish()
        diagnostics.flush()
        finishBroadcastWithError(NSError(domain: "CarMirror", code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }

    private func tearDown(stopHeartbeat: Bool = true) {
        if stopHeartbeat {
            heartbeat?.cancel()
            heartbeat = nil
        }
        if #available(iOS 26, *) { (captionService as? LiveCaptionTranscriber)?.stop() }
        captionService = nil
        encoder?.stop()
        server?.stop()
        buffer?.invalidate()
        encoder = nil
        server = nil
        buffer = nil
    }
}
