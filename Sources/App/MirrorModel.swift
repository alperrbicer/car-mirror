import Foundation
import Combine
import SwiftUI
@preconcurrency import GoogleCast

@MainActor
final class MirrorModel: ObservableObject {
    static let shared = MirrorModel()
    @Published private(set) var capture: CaptureStatus?
    @Published var errorMessage: String?
    @Published private(set) var storageReady = false
    @Published private(set) var sessionState: MirrorSessionState = .waitingForDisplay
    @Published private(set) var externalScreenCount = 0
    @Published private(set) var probeStartedAt: Date?
    @Published private(set) var mediaTitle: String?
    @Published private(set) var selectedMediaChannel: MediaChannel?
    @Published private(set) var mediaErrorMessage: String?
    @Published var presentingPlayer = false
    @Published private(set) var playerScreenVisible = false
    @Published private(set) var playbackQueue: [MediaChannel] = []
    var playbackSourceID: UUID? { mediaSourceID }
    var playbackSource: MediaSource? {
        guard let mediaSourceID else { return nil }
        return SourceLibrary.shared.sources.first { $0.id == mediaSourceID }
    }
    private var advancesQueue = false
    @Published private(set) var dailyRemaining: TimeInterval = DailyViewingBudget.limit
    private var viewingBudget = (UserDefaults.standard.data(forKey: "dailyViewingBudget").flatMap { try? JSONDecoder().decode(DailyViewingBudget.self, from: $0) }) ?? DailyViewingBudget(now: Date())
    private var viewingCheckpoint = Date()
    private var wasViewing = false
    private var viewingObserver: AnyCancellable?
    private var historyObserver: AnyCancellable?
    private var pendingPlayerRestores: [(Bool) -> Void] = []
    private var mediaPresentation: MediaPlaybackPresentation?
    private var mediaSourceID: UUID?
    private var resumeCheckpoint = Date.distantPast
    private var resumeRecordingEnabled = false
    private var backgroundObserver: NSObjectProtocol?
    let playback = PlaybackController()
    let diagnostics = SessionDiagnostics(process: .app)
    private var store: BroadcastSessionStore?
    private var timer: Timer?
    private var playbackSessionID: UUID?
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
        playback.onRestorePlayer = { [weak self] completion in
            guard let self, self.selectedMediaChannel != nil else { completion(false); return }
            if self.playerScreenVisible { completion(true) }
            else {
                self.pendingPlayerRestores.append(completion)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.presentingPlayer = true }
            }
        }
        playback.onRemoteStop = { [weak self] in self?.stopBroadcast() }
        playback.onFinished = { [weak self] in
            guard let self else { return }
            if self.resumeRecordingEnabled, let last = LastPlaybackStore.shared.record,
               last.channel.id == self.selectedMediaChannel?.id, !last.isLive, last.duration > 0 {
                try? LastPlaybackStore.shared.save(LastPlaybackRecord(channel: last.channel, sourceID: last.sourceID,
                    position: last.duration, duration: last.duration, isLive: false))
            }
            if self.advancesQueue, let next = self.adjacentChannel(1) {
                self.playMedia(next)
            } else {
                self.stopProbe()
                self.stopPlayback()
            }
        }
        record(.appOpened)
        playback.onFailure = { [weak self] message in
            guard let self else { return }
            self.mediaTitle = nil
            if self.selectedMediaChannel != nil { self.mediaErrorMessage = message }
            self.playbackAttemptFailed = self.playbackSessionID != nil
            self.errorMessage = message
            self.updateSessionState()
        }
        viewingObserver = playback.$isPlaying.sink { [weak self] playing in
            self?.accountViewingTime()
            self?.wasViewing = playing && self?.selectedMediaChannel != nil && self?.playback.hasActivePlayback == true
        }
        historyObserver = playback.$state.sink { [weak self] state in
            if state == .playing || state == .paused {
                Task { @MainActor in self?.saveLastPlayback(force: true) }
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.saveLastPlayback(force: true) }
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
        case .waitingForDisplay: return L10n.tr("TV’ye bağlan")
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
        accountViewingTime()
        saveLastPlayback()
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
        if probeStartedAt == nil, (externalScreenCount > 0 || playback.tvDevice != nil), readyToPlay,
           stopRequestedID == nil, capture?.sessionID != lastAttemptedSessionID {
            playOnDisplay()
        }
        updateSessionState()
    }

    func foregrounded() { record(.appForegrounded); refresh(); Task { await PurchaseStore.shared.refresh() } }

    func playOnDisplay() {
        guard AppUpdateStore.shared.requiredURL == nil else { return }
        guard externalScreenCount > 0 || playback.tvDevice != nil else {
            errorMessage = L10n.tr("TV’ye bağlan")
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
        guard let url = externalScreenCount > 0 && playback.tvDevice == nil ? capture.loopbackURL : capture.networkURL else {
            errorMessage = L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene.")
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
                requiresExternalPlayback: externalScreenCount == 0 && playback.tvDevice == nil)
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

    func connectTV(_ renderer: GCKDevice) {
        do {
            try playback.setTVDevice(renderer)
            if broadcasting { lastAttemptedSessionID = nil; refresh() }
            if playback.hasActivePlayback, let channel = selectedMediaChannel {
                mediaTitle = channel.title; mediaErrorMessage = nil; errorMessage = nil
            }
        } catch {
            playback.stop()
            mediaTitle = nil
            errorMessage = L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene.")
            mediaErrorMessage = errorMessage
        }
        updateSessionState()
    }

    func disconnectTV() {
        guard playback.tvDevice != nil else { return }
        // Do not loop the phone's own screen capture back onto its display.
        if playbackSessionID != nil { stopBroadcast() }
        do {
            try playback.setTVDevice(nil)
            if playback.hasActivePlayback, let channel = selectedMediaChannel {
                mediaTitle = channel.title; mediaErrorMessage = nil; errorMessage = nil
            }
        }
        catch {
            playback.stop()
            mediaTitle = nil
            mediaErrorMessage = L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
        }
        updateSessionState()
    }

    @discardableResult
    func playMedia(_ channel: MediaChannel, presentation: MediaPlaybackPresentation? = nil, queue: [MediaChannel]? = nil,
                   advanceAutomatically: Bool = false, sourceID: UUID? = nil, startAt: Double = 0) -> Bool {
        guard AppUpdateStore.shared.requiredURL == nil else { return false }
        accountViewingTime()
        guard PurchaseStore.shared.access.fullAccess || dailyRemaining > 0 else {
            errorMessage = L10n.tr("Günlük 2 saatlik izleme sınırına ulaştın. Yarın yeniden izleyebilirsin.")
            return false
        }
        if selectedMediaChannel == channel, playback.hasActivePlayback {
            // Selecting the already-playing channel from a category must still
            // replace the playlist queue with that category's filtered items.
            let nextQueue = queue ?? playbackQueue
            if sourceID == nil || sourceID != mediaSourceID {
                removeReleasedPersonalMedia(from: playbackQueue, keeping: nextQueue)
            }
            playbackQueue = nextQueue
            if queue != nil { advancesQueue = advanceAutomatically }
            if let sourceID { mediaSourceID = sourceID }
            return true
        }
        let nextQueue = queue ?? (playbackQueue.contains(where: { $0.id == channel.id }) ? playbackQueue : [channel])
        let nextSourceID = sourceID ?? (playbackQueue.contains(where: { $0.id == channel.id }) ? mediaSourceID : nil)
        // IPTV channel selection keeps the same source queue. Personal-media
        // cleanup only matters when leaving a local-media queue or changing
        // between unscoped personal-media queues.
        if sourceID == nil || sourceID != mediaSourceID {
            removeReleasedPersonalMedia(from: playbackQueue, keeping: nextQueue)
        }
        let shouldAdvance = queue != nil ? advanceAutomatically : (playbackQueue.contains(where: { $0.id == channel.id }) && advancesQueue)
        let keepPlayerPresented = presentingPlayer
        if playback.tvDevice != nil && playback.hasActivePlayback {
            // Keep the Cast receiver loaded until PlaybackController submits
            // the replacement media; stopping playback here forces an extra
            // STOP/load round trip for every channel selection.
            stopProbe()
            stopBroadcastCapture()
        } else {
            stopBroadcast()
        }
        presentingPlayer = keepPlayerPresented
        playbackQueue = nextQueue
        advancesQueue = shouldAdvance
        errorMessage = nil
        selectedMediaChannel = channel
        mediaSourceID = nextSourceID
        resumeRecordingEnabled = true
        resumeCheckpoint = .distantPast
        mediaPresentation = presentation
        let resolvedPresentation: MediaPlaybackPresentation = presentation ?? (channel.isAudio ? .audio : .video)
        do {
            try playback.play(url: channel.url, preserveSourceAudio: false, requiresExternalPlayback: false,
                              title: channel.title, live: channel.isLive, presentation: resolvedPresentation,
                              useCompatibility: channel.requiresCompatibilityPlayback, startAt: startAt)
            guard playback.hasActivePlayback else { return false }
            mediaTitle = channel.title
            return true
        } catch {
            playback.stop()
            errorMessage = L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
            mediaErrorMessage = errorMessage
            return false
        }
    }

    private func removeReleasedPersonalMedia(from previousQueue: [MediaChannel], keeping nextQueue: [MediaChannel]) {
        // Channel changes normally keep the same source queue. Detect that in
        // one linear pass; only build a lookup set when the queue actually
        // changes. Avoid the former nested `contains` scan on large playlists.
        if previousQueue.count == nextQueue.count,
           zip(previousQueue, nextQueue).allSatisfy({ $0.0.id == $0.1.id }) { return }
        let retainedIDs = Set(nextQueue.map(\.id))
        let releasedFiles = previousQueue.compactMap { retainedIDs.contains($0.id) ? nil : $0.url }
        if !releasedFiles.isEmpty { PersonalMediaFiles.remove(releasedFiles) }
    }

    func adjacentChannel(_ offset: Int) -> MediaChannel? {
        guard let current = selectedMediaChannel,
              let index = playbackQueue.firstIndex(where: { $0.id == current.id }),
              playbackQueue.indices.contains(index + offset) else { return nil }
        return playbackQueue[index + offset]
    }
    func restorePlaybackQueueFromSource() async {
        guard let sourceID = mediaSourceID, let selectedMediaChannel,
              let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) else { return }
        let selectedChannelID = selectedMediaChannel.id
        let channels: [MediaChannel]
        if let cached = SourceLibrary.shared.cachedChannels(for: source) {
            channels = cached
        } else {
            do { channels = try await SourceLibrary.shared.channels(for: source) }
            catch { return }
        }
        guard mediaSourceID == sourceID, self.selectedMediaChannel?.id == selectedChannelID,
              channels.contains(where: { $0.id == selectedChannelID }) else { return }
        playbackQueue = channels
    }
    func switchChannel(_ offset: Int) {
        guard let channel = adjacentChannel(offset) else { return }
        playMedia(channel)
    }
    private func accountViewingTime() {
        let now = Date()
        viewingBudget.record(from: viewingCheckpoint, to: now,
                             playing: wasViewing && !PurchaseStore.shared.access.fullAccess)
        viewingCheckpoint = now
        dailyRemaining = viewingBudget.remaining
        if let data = try? JSONEncoder().encode(viewingBudget) { UserDefaults.standard.set(data, forKey: "dailyViewingBudget") }
        if dailyRemaining == 0, !PurchaseStore.shared.access.fullAccess, wasViewing {
            wasViewing = false
            playback.stop()
            mediaTitle = nil
            mediaErrorMessage = L10n.tr("Günlük 2 saatlik izleme sınırına ulaştın. Yarın yeniden izleyebilirsin.")
            errorMessage = mediaErrorMessage
        }
    }

    func resetDailyViewingBudget() {
        let now = Date()
        viewingBudget = DailyViewingBudget(now: now)
        viewingCheckpoint = now
        dailyRemaining = DailyViewingBudget.limit
        if let data = try? JSONEncoder().encode(viewingBudget) {
            UserDefaults.standard.set(data, forKey: "dailyViewingBudget")
        }
    }

    func playerVisibilityChanged(_ visible: Bool) {
        playerScreenVisible = visible
        if visible { finishPlayerRestoration(true) }
    }
    private func finishPlayerRestoration(_ restored: Bool) {
        let completions = pendingPlayerRestores
        pendingPlayerRestores.removeAll()
        completions.forEach { $0(restored) }
    }

    func retryMedia() {
        guard let channel = selectedMediaChannel else { return }
        playMedia(channel, presentation: mediaPresentation)
    }

    private func saveLastPlayback(force: Bool = false) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-pip-probe") { return }
        #endif
        guard resumeRecordingEnabled, let channel = selectedMediaChannel, !channel.isAudio, !channel.url.isFileURL,
              mediaTitle != nil, playback.state == .playing || playback.state == .paused else { return }
        let now = Date()
        guard force || now.timeIntervalSince(resumeCheckpoint) >= 5 else { return }
        let record = LastPlaybackRecord(channel: channel, sourceID: mediaSourceID,
                                        position: playback.currentTime, duration: playback.duration, isLive: playback.isLive)
        do { try LastPlaybackStore.shared.save(record); resumeCheckpoint = now }
        catch { /* A history write must not interrupt playback. */ }
    }

    @discardableResult
    func resumeLastPlayback() -> Bool {
        guard let last = LastPlaybackStore.shared.record else { return false }
        return resumePlayback(last)
    }

    @discardableResult
    func resumePlayback(_ last: LastPlaybackRecord) -> Bool {
        if let sourceID = last.sourceID, !SourceLibrary.shared.sources.contains(where: { $0.id == sourceID }) {
            try? LastPlaybackStore.shared.clear(sourceID: sourceID)
            return false
        }
        return playMedia(last.channel, sourceID: last.sourceID, startAt: last.resumePosition)
    }

    var activeContinuationID: String? {
        guard playback.hasActivePlayback, let channel = selectedMediaChannel else { return nil }
        return LastPlaybackRecord(channel: channel, sourceID: mediaSourceID, position: 0, duration: 0, isLive: playback.isLive).id
    }

    func removeContinuation(_ id: String) throws {
        try LastPlaybackStore.shared.remove(id: id)
        if activeContinuationID == id { resumeRecordingEnabled = false }
    }

    func discardLastPlayback(sourceID: UUID? = nil) {
        if sourceID == nil || mediaSourceID == sourceID { resumeRecordingEnabled = false }
        try? LastPlaybackStore.shared.clear(sourceID: sourceID)
    }

    func stopPlayback(clearLastPlayback: Bool = false) {
        if clearLastPlayback {
            let continuationID = activeContinuationID
            resumeRecordingEnabled = false
            if let continuationID { try? LastPlaybackStore.shared.remove(id: continuationID) }
        } else {
            saveLastPlayback(force: true)
        }
        finishPlayerRestoration(false)
        presentingPlayer = false
        playback.stop()
        mediaTitle = nil
        selectedMediaChannel = nil
        mediaPresentation = nil
        mediaSourceID = nil
        mediaErrorMessage = nil
        advancesQueue = false
        playbackSessionID = nil
        playbackAttemptFailed = false
    }

    func stopBroadcast() {
        stopProbe()
        stopPlayback()
        stopBroadcastCapture()
    }

    private func stopBroadcastCapture() {
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
        playback.externalDisplayConnected = externalScreenCount > 0
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
        playback.externalDisplayConnected = externalScreenCount > 0
        record(.externalScreenDisconnected)
        if externalScreenCount == 0 { stopProbe(); if playbackSessionID != nil { stopBroadcast() } }
    }

    func startExternalProbe() {
        guard !broadcasting, externalScreenCount > 0 else { return }
        probeStartedAt = Date()
        record(.probeStarted)
        scheduleProbeEnd()
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
        sessionState = .resolve(capture: capture, displayConnected: externalScreenCount > 0 || playback.tvDevice != nil,
            playbackSessionID: playbackSessionID, externalPlayback: playback.externalPlaybackActive || ((externalScreenCount > 0 || playback.tvDevice != nil) && playbackSessionID == capture?.sessionID),
            playing: playback.isPlaying, stopRequested: stopRequestedID == capture?.sessionID && stopRequestedID != nil,
            playbackFailed: playbackAttemptFailed || playback.errorMessage != nil)
    }
}
