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

    private init() {
        do { store = try BroadcastSessionStore(); storageReady = true }
        catch { errorMessage = "Paylaşım hazırlanamadı. Uygulamayı yeniden açmayı dene." }
        playback.onDiagnostic = { [weak self] kind, values in self?.record(kind, values: values) }
        playback.onFinished = { [weak self] in self?.stopProbe() }
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
        case .waitingForCar: return "Aracına bağlan"
        case .ready: return "Paylaşıma hazır"
        case .preparing: return "Yayın hazırlanıyor"
        case .captureReady: return "Ekran yayını hazır"
        case .connecting: return "Görüntü bağlanıyor"
        case .presenting: return "Ekran paylaşımı etkin"
        case .paused: return "Yayın duraklatıldı"
        case .stopping: return "Paylaşım durduruluyor"
        case .interrupted: return "Yayın bağlantısı kesildi"
        case .failed: return "Yayın tamamlanamadı"
        }
    }

    var carTitle: String {
        if !carPlayConnected { return "Araç ekranında CarMirror’ı aç" }
        return "CarPlay bağlı"
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
        if probeStartedAt == nil, carPlayConnected, supportsVideo == true, readyToPlay,
           stopRequestedID == nil, capture?.sessionID != lastAttemptedSessionID {
            playInCar()
        }
        updateSessionState()
    }

    func foregrounded() { record(.appForegrounded); refresh() }

    func connected(supportsVideo: Bool?) {
        carPlayConnected = true
        self.supportsVideo = supportsVideo
        var values = DiagnosticValues()
        values.screen = .carPlay
        values.supportsVideo = supportsVideo
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
        guard carPlayConnected else {
            errorMessage = "Önce araç ekranında CarMirror’ı aç."
            return
        }
        guard supportsVideo == true else {
            errorMessage = "CarPlay video çıkışı kullanılamıyor."
            return
        }
        guard let capture, capture.canPlay() else {
            errorMessage = "Önce iPhone’da ekran yayınını başlat."
            return
        }
        lastAttemptedSessionID = capture.sessionID
        playbackAttemptFailed = false
        errorMessage = nil
        // A receiver cannot fetch 127.0.0.1 on the phone. Do not silently substitute it.
        guard let url = capture.networkURL else {
            errorMessage = "Araç için yayın bağlantısı kurulamadı."
            playbackAttemptFailed = true
            var values = DiagnosticValues()
            values.reason = .unavailable
            record(.failure, values: values)
            updateSessionState()
            return
        }
        do {
            record(.playbackRequested)
            try playback.play(url: url)
            playbackSessionID = capture.sessionID
        } catch {
            playback.stop()
            playbackAttemptFailed = true
            errorMessage = "Görüntü başlatılamadı. Yeniden deneyebilirsin."
            var values = DiagnosticValues()
            values.reason = .playback
            values.failure = DiagnosticFailure(error)
            record(.failure, values: values)
        }
        updateSessionState()
    }

    func stopPlayback() {
        playback.stop()
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
            errorMessage = "Paylaşım durdurulamadı. Yeniden deneyebilirsin."
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
    }

    func externalScreenDisconnected(_ id: UUID) {
        externalScreens.remove(id)
        externalScreenCount = externalScreens.count
        record(.externalScreenDisconnected)
        if externalScreenCount == 0 { stopProbe() }
    }

    func startExternalProbe() {
        guard !broadcasting, externalScreenCount > 0 else { return }
        probeStartedAt = Date()
        record(.probeStarted)
    }

    func startVideoProbe() {
        guard !broadcasting, carPlayConnected, supportsVideo == true,
              let url = Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4") else { return }
        do {
            probeStartedAt = Date()
            record(.probeStarted)
            try playback.play(url: url, preserveSourceAudio: false)
        } catch {
            errorMessage = "Bağlantı testi başlatılamadı."
            var values = DiagnosticValues()
            values.failure = DiagnosticFailure(error)
            record(.failure, values: values)
            stopProbe()
        }
    }

    func stopProbe() {
        guard probeStartedAt != nil else { return }
        record(.probeStopped)
        probeStartedAt = nil
        stopPlayback()
        updateSessionState()
    }

    private func updateSessionState() {
        sessionState = .resolve(capture: capture, carConnected: carPlayConnected,
            playbackSessionID: playbackSessionID, externalPlayback: playback.externalPlaybackActive,
            playing: playback.isPlaying, stopRequested: stopRequestedID == capture?.sessionID && stopRequestedID != nil,
            playbackFailed: playbackAttemptFailed || playback.errorMessage != nil)
    }
}
