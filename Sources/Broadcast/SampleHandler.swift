import ReplayKit
import ImageIO

final class SampleHandler: RPBroadcastSampleHandler {
    private let stateQueue = DispatchQueue(label: "CarMirror.BroadcastState")
    private var store: BroadcastSessionStore?
    private var status = CaptureStatus()
    private var buffer: HLSBuffer?
    private var encoder: ScreenStreamEncoder?
    private var server: LocalStreamServer?
    private var heartbeat: DispatchSourceTimer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        stateQueue.async { [self] in
            do {
                store = try BroadcastSessionStore()
                try begin()
            } catch { fail(error.localizedDescription) }
        }
    }

    override func broadcastPaused() {
        stateQueue.async { [self] in
            tearDown()
            status.phase = .paused
            publish()
        }
    }

    override func broadcastResumed() {
        stateQueue.async { [self] in
            do { try begin() } catch { fail(error.localizedDescription) }
        }
    }

    override func broadcastFinished() {
        stateQueue.sync {
            tearDown()
            if status.phase != .failed { status.phase = .stopped }
            publish()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Audio remains with the source app on the vehicle's existing audio route.
        guard sampleBufferType == .video, let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber
        let orientation = CGImagePropertyOrientation(rawValue: value?.uint32Value ?? 1) ?? .up
        stateQueue.sync { encoder?.submit(image, orientation: orientation) }
    }

    private func begin() throws {
        tearDown()
        status = CaptureStatus()
        try store?.write(status)
        let sessionID = status.sessionID
        let buffer = HLSBuffer()
        let encoder = ScreenStreamEncoder(buffer: buffer)
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
                self?.fail("Yerel yayın açılamadı: \(error.localizedDescription)")
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
        if store?.shouldStop(sessionID: status.sessionID) == true {
            tearDown()
            status.phase = .stopped
            publish()
            finishBroadcastWithError(NSError(domain: "CarMirror", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Ekran paylaşımı senin isteğinle durduruldu."]))
            return
        }
        guard let encoder, let buffer else { return }
        let stats = encoder.snapshot()
        if let failure = stats.failure { fail(failure); return }
        let contents = buffer.snapshot()
        status.receivedFrames = stats.received
        status.encodedFrames = stats.encoded
        status.droppedFrames = stats.dropped
        status.segmentCount = contents.totalSegments
        status.bufferedBytes = contents.byteCount
        if contents.isReady && status.loopbackURL != nil { status.phase = .live }
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
            tearDown()
            finishBroadcastWithError(error)
        }
    }

    private func fail(_ message: String) {
        tearDown()
        status.phase = .failed
        status.message = message
        publish()
        finishBroadcastWithError(NSError(domain: "CarMirror", code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }

    private func tearDown() {
        heartbeat?.cancel()
        heartbeat = nil
        encoder?.stop()
        server?.stop()
        buffer?.invalidate()
        encoder = nil
        server = nil
        buffer = nil
    }
}
