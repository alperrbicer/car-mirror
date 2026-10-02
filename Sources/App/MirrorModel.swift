import Foundation
import Combine
import CarPlay

@MainActor
final class MirrorModel: ObservableObject {
    static let shared = MirrorModel()
    @Published private(set) var capture: CaptureStatus?
    @Published private(set) var carPlayConnected = false
    @Published private(set) var supportsVideo: Bool?
    @Published var errorMessage: String?
    @Published private(set) var storageReady = false
    @Published private(set) var sessionState: MirrorSessionState = .waitingForCar
    @Published private(set) var externalScreenCount = 0
    @Published private(set) var probeStartedAt: Date?
    @Published private(set) var mediaTitle: String?
    let playback = PlaybackController()
    let diagnostics = SessionDiagnostics(process: .app)
    private var store: BroadcastSessionStore?
    private var timer: Timer?
    private var playbackSessionID: UUID?
    private var playbackFailureObservation: AnyCancellable?
    private var playbackAttemptFailed = false
    private var connectionSessionID = UUID()
    private var stopRequestedID: UUID?
    private var lastAttemptedSessionID: UUID?
    private var lastCapturePhase: CapturePhase?
    private var lastCaptureID: UUID?
    private var staleSessionID: UUID?
    private var externalScreens: Set<UUID> = []
    private var probeTask: Task<Void, Never>?

    private init() {
        do { store = try BroadcastSessionStore(); storageReady = true }
        catch { errorMessage = L10n.tr("Paylaşım hazırlanamadı. Uygulamayı yeniden açmayı dene.") }
        playback.onDiagnostic = { [weak self] kind, values in self?.record(kind, values: values) }
        playback.onRemoteStop = { [weak self] in self?.stopBroadcast() }
        playback.onFinished = { [weak self] in
            self?.stopProbe()
            self?.mediaTitle = nil
        }
        record(.appOpened)
        playbackFailureObservation = playback.$errorMessage
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
                self?.updateSessionState()
            }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var readyToPlay: Bool { capture?.canPlay() == true }
    var broadcasting: Bool {
        guard let capture else { return false }
        return capture.isFresh() && [.preparing, .live, .paused].contains(capture.phase)
    }

    var captureTitle: String {
        switch sessionState {
        case .waitingForCar: return L10n.tr("Aracına bağlan")
        case .ready: return L10n.tr("Paylaşıma hazır")
        case .preparing: return L10n.tr("Yayın hazırlanıyor")
        case .captureReady: return L10n.tr("Ekran yayını hazır")
        case .connecting: return L10n.tr("Görüntü bağlanıyor")
        case .presenting: return L10n.tr("Ekran paylaşımı etkin")
        case .paused: return L10n.tr("Yayın duraklatıldı")
        case .stopping: return L10n.tr("Paylaşım durduruluyor")
        case .interrupted: return L10n.tr("Yayın bağlantısı kesildi")
        case .failed: return L10n.tr("Yayın tamamlanamadı")
        }
    }

    func refresh() {
        capture = store?.readStatus()
        if capture?.sessionID != lastCaptureID { playbackAttemptFailed = false }
        if broadcasting, probeStartedAt != nil { stopProbe() }
        if capture?.sessionID != lastCaptureID || capture?.phase != lastCapturePhase {
            lastCaptureID = capture?.sessionID
            lastCapturePhase = capture?.phase
            if let capture {
                var values = DiagnosticValues()
                values.capturePhase = capture.phase
                record(.capturePhaseChanged, values: values)
            }
        }
        if let capture, !capture.isFresh(), [.live, .preparing, .paused].contains(capture.phase),
           staleSessionID != capture.sessionID {
            staleSessionID = capture.sessionID
            record(.captureStale)
        }
        if let playbackSessionID,
           capture?.sessionID != playbackSessionID || !readyToPlay {
            stopPlayback()
        }
        if let stopRequestedID, capture?.sessionID != stopRequestedID || !broadcasting {
            self.stopRequestedID = nil
        }
        if probeStartedAt == nil, (carPlayConnected && supportsVideo == true || externalScreenCount > 0), readyToPlay,
           stopRequestedID == nil, capture?.sessionID != lastAttemptedSessionID {
            playInCar()
        }
        updateSessionState()
    }

    func foregrounded() { record(.appForegrounded); refresh(); Task { await PurchaseStore.shared.refresh() } }

    func connected(supportsVideo: Bool?) {
        carPlayConnected = true
        self.supportsVideo = CarPlayCapabilities.current.canPresentVideo(vehicleSupportsVideo: supportsVideo)
        var values = DiagnosticValues()
        values.screen = .carPlay
        values.supportsVideo = self.supportsVideo
        record(.carConnected, values: values)
        refresh()
    }

    func disconnected() {
        var values = DiagnosticValues()
        values.reason = .disconnected
        record(.carDisconnected, values: values)
        carPlayConnected = false
        supportsVideo = nil
        stopBroadcast()
        stopProbe()
        updateSessionState()
    }

    func playInCar() {
        guard carPlayConnected || externalScreenCount > 0 else {
            errorMessage = L10n.tr("CarPlay’e bağlanıp araç ekranında uygulamayı aç.")
            return
        }
        guard supportsVideo == true || externalScreenCount > 0 else {
            errorMessage = L10n.tr("CarPlay video çıkışı kullanılamıyor.")
            return
        }
        guard let capture, capture.canPlay() else {
            errorMessage = L10n.tr("Önce iPhone’da ekran yayınını başlat.")
            return
        }
        lastAttemptedSessionID = capture.sessionID
        playbackAttemptFailed = false
        errorMessage = nil
        // A receiver cannot fetch 127.0.0.1 on the phone. Do not silently substitute it.
        guard let url = externalScreenCount > 0 ? capture.loopbackURL : capture.networkURL else {
            errorMessage = L10n.tr("Araç için yayın bağlantısı kurulamadı.")
            playbackAttemptFailed = true
            var values = DiagnosticValues()
            values.reason = .unavailable
            record(.failure, values: values)
            updateSessionState()
            return
        }
        do {
            record(.playbackRequested)
            mediaTitle = nil
            try playback.play(url: url, muted: capture.audioMode == .source,
                requiresExternalPlayback: externalScreenCount == 0)
            playbackSessionID = capture.sessionID
        } catch {
            playback.stop()
            playbackAttemptFailed = true
            errorMessage = L10n.tr("Görüntü başlatılamadı. Yeniden deneyebilirsin.")
            var values = DiagnosticValues()
            values.reason = .playback
            values.failure = DiagnosticFailure(error)
            record(.failure, values: values)
        }
        updateSessionState()
    }

    @discardableResult
    func playMedia(_ channel: MediaChannel, presentation: MediaPlaybackPresentation? = nil) -> Bool {
        stopBroadcast()
        errorMessage = nil
        let resolvedPresentation: MediaPlaybackPresentation = carPlayConnected && supportsVideo != true ? .audio : (presentation ?? .video)
        do {
            try playback.play(url: channel.url, preserveSourceAudio: false, requiresExternalPlayback: false,
                              title: channel.title, presentation: resolvedPresentation)
            mediaTitle = channel.title
            return true
        } catch {
            playback.stop()
            errorMessage = L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
            return false
        }
    }

    func stopPlayback() {
        playback.stop()
        mediaTitle = nil
        playbackSessionID = nil
        playbackAttemptFailed = false
    }

    func stopBroadcast() {
        stopProbe()
        stopPlayback()
        guard let capture, broadcasting else { updateSessionState(); return }
        do {
            try store?.requestStop(sessionID: capture.sessionID)
            stopRequestedID = capture.sessionID
            var values = DiagnosticValues()
            values.reason = .user
            record(.stopRequested, values: values)
        }
        catch {
            errorMessage = L10n.tr("Paylaşım durdurulamadı. Yeniden deneyebilirsin.")
            var values = DiagnosticValues()
            values.reason = .storage
            values.failure = DiagnosticFailure(error)
            record(.failure, values: values)
        }
        updateSessionState()
    }

    func record(_ kind: DiagnosticKind, values: DiagnosticValues = DiagnosticValues()) {
        diagnostics.record(kind, sessionID: capture?.sessionID ?? connectionSessionID, values: values)
    }

    func externalScreenConnected(_ id: UUID, role: DiagnosticValues.Screen, size: CGSize) {
        externalScreens.insert(id)
        externalScreenCount = externalScreens.count
        var values = DiagnosticValues()
        values.screen = role
        values.width = Int(size.width)
        values.height = Int(size.height)
        record(.externalScreenConnected, values: values)
        refresh()
    }

    func externalScreenDisconnected(_ id: UUID) {
        externalScreens.remove(id)
        externalScreenCount = externalScreens.count
        record(.externalScreenDisconnected)
        if externalScreenCount == 0 { stopProbe(); if playbackSessionID != nil { stopBroadcast() } }
    }

    func startExternalProbe() {
        guard !broadcasting, externalScreenCount > 0 else { return }
        probeStartedAt = Date()
        record(.probeStarted)
        scheduleProbeEnd()
    }

    func startVideoProbe() {
        guard !broadcasting, carPlayConnected, supportsVideo == true,
              let url = Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4") else { return }
        do {
            probeStartedAt = Date()
            record(.probeStarted)
            try playback.play(url: url, preserveSourceAudio: false)
            scheduleProbeEnd()
        } catch {
            errorMessage = L10n.tr("Bağlantı testi başlatılamadı.")
            var values = DiagnosticValues()
            values.failure = DiagnosticFailure(error)
            record(.failure, values: values)
            stopProbe()
        }
    }

    func stopProbe() {
        guard probeStartedAt != nil else { return }
        probeTask?.cancel(); probeTask = nil
        record(.probeStopped)
        probeStartedAt = nil
        stopPlayback()
        updateSessionState()
    }

    private func scheduleProbeEnd() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.stopProbe()
        }
    }

    private func updateSessionState() {
        sessionState = .resolve(capture: capture, carConnected: carPlayConnected || externalScreenCount > 0,
            playbackSessionID: playbackSessionID, externalPlayback: playback.externalPlaybackActive || (externalScreenCount > 0 && playbackSessionID == capture?.sessionID),
            playing: playback.isPlaying, stopRequested: stopRequestedID == capture?.sessionID && stopRequestedID != nil,
            playbackFailed: playbackAttemptFailed || playback.errorMessage != nil)
    }
}
