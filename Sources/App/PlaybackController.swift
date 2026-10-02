import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    enum State { case idle, loading, playing, paused, failed }
    let player = AVPlayer()
    @Published private(set) var state: State = .idle
    var hasActivePlayback: Bool { state == .loading || state == .playing || state == .paused }
    var canUseVehicleMode: Bool { state == .playing || state == .paused }
    @Published private(set) var externalPlaybackActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private var externalObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var playingObservation: NSKeyValueObservation?
    private var activatedAudioSession = false
    private var waitingForExternalPlayback = false
    var onDiagnostic: ((DiagnosticKind, DiagnosticValues) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onRemoteStop: (() -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []
    private var startupTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var interruptionItem: AVPlayerItem?
    private var wasPlayingBeforeInterruption = false
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init() {
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.isMuted = true
        externalObservation = player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                let active = self.player.currentItem != nil && self.player.isExternalPlaybackActive
                if active { self.startupTask?.cancel(); self.startupTask = nil; self.waitingForExternalPlayback = false }
                if self.externalPlaybackActive != active {
                    self.externalPlaybackActive = active
                    var values = DiagnosticValues()
                    values.externalPlayback = active
                    self.onDiagnostic?(.externalPlaybackChanged, values)
                }
            }
        }
        playingObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = self.player.currentItem != nil && self.player.timeControlStatus == .playing
                if self.player.currentItem != nil {
                    switch self.player.timeControlStatus {
                    case .playing: self.state = .playing
                    case .waitingToPlayAtSpecifiedRate: self.state = .loading
                    default: if self.state != .loading { self.state = .paused }
                    }
                }
                if self.isPlaying && !self.waitingForExternalPlayback { self.startupTask?.cancel(); self.startupTask = nil }
                if self.activatedAudioSession {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
                }
                var values = DiagnosticValues()
                switch self.player.timeControlStatus {
                case .playing: values.playback = .playing
                case .waitingToPlayAtSpecifiedRate: values.playback = .waiting
                default: values.playback = .stopped
                }
                self.onDiagnostic?(.playbackState, values)
            }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recordAudioRoute() }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                Task { @MainActor in
                    guard let self else { return }
                    var values = DiagnosticValues()
                    values.reason = .interrupted
                    self.onDiagnostic?(.audioInterrupted, values)
                    if began {
                        self.wasPlayingBeforeInterruption = self.player.rate > 0
                        self.interruptionItem = self.player.currentItem
                        self.player.pause()
                    } else {
                        let flags = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                        if flags & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0,
                           self.wasPlayingBeforeInterruption, self.player.currentItem === self.interruptionItem {
                            try? AVAudioSession.sharedInstance().setActive(true)
                            self.player.play()
                        }
                        self.interruptionItem = nil
                    }
                }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let item = note.object as? AVPlayerItem else { return }
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.stallTask?.cancel()
                    self.stallTask = Task { [weak self, weak item] in
                        try? await Task.sleep(for: .seconds(12))
                        guard !Task.isCancelled, let self, let item, self.player.currentItem === item,
                              self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
                        self.fail(L10n.tr("Yayın bağlantısı kesildi. Yeniden deneyebilirsin."), reason: .interrupted)
                    }
                }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let item = notification.object as? AVPlayerItem else { return }
                let failure = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error).map(DiagnosticFailure.init)
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    self.fail(L10n.tr("Yayın bağlantısı kesildi. Yeniden deneyebilirsin."), reason: .playback, failure: failure)
                }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let item = notification.object as? AVPlayerItem else { return }
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    var values = DiagnosticValues()
                    values.playback = .stopped
                    values.reason = .finished
                    self.onDiagnostic?(.playbackState, values)
                    self.stop()
                    self.onFinished?()
                }
            })
    }

    deinit { notificationTokens.forEach(NotificationCenter.default.removeObserver) }

    func play(url: URL, preserveSourceAudio: Bool = true, muted: Bool = false,
              requiresExternalPlayback: Bool = true, title: String? = nil, live: Bool = true,
              presentation: MediaPlaybackPresentation = .video) throws {
        stop()
        errorMessage = nil
        // Mixing avoids deliberately taking over the source application's audio.
        let session = AVAudioSession.sharedInstance()
        if presentation == .audio {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        } else if preserveSourceAudio {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        } else {
            try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
        }
        try session.setActive(true)
        activatedAudioSession = true
        waitingForExternalPlayback = requiresExternalPlayback && presentation == .video
        player.isMuted = muted
        player.allowsExternalPlayback = presentation == .video
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            guard let item, item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."),
                          reason: .playback, failure: item.error.map(DiagnosticFailure.init))
            }
        }
        state = .loading
        player.replaceCurrentItem(with: item)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title ?? L10n.tr("iPhone ekranı"),
            MPMediaItemPropertyArtist: BrandIdentity.name,
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyMediaType: presentation == .audio ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0
        ]
        player.play()
        installRemoteCommands()
        recordAudioRoute()
        startupTask = Task { [weak self, weak item] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, let item, self.player.currentItem === item,
                  (requiresExternalPlayback && presentation == .video ? !self.player.isExternalPlaybackActive : self.player.timeControlStatus != .playing) else { return }
            self.fail(L10n.tr(requiresExternalPlayback && presentation == .video ? "Araç görüntüsü kurulamadı. Yeniden deneyebilirsin." : "Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .unavailable)
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        waitingForExternalPlayback = false
        stallTask?.cancel(); stallTask = nil
        interruptionItem = nil
        remoteTargets.forEach { $0.0.removeTarget($0.1); $0.0.isEnabled = false }; remoteTargets.removeAll()
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if activatedAudioSession { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        isPlaying = false
        state = .idle
        errorMessage = nil
        externalPlaybackActive = false
        player.allowsExternalPlayback = false
        if activatedAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            activatedAudioSession = false
        }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.rate > 0 { pause() } else { player.play() }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
    }

    private func pause() {
        startupTask?.cancel(); startupTask = nil
        player.pause()
        state = .paused
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        for (command, action) in [(center.playCommand, 0), (center.pauseCommand, 1), (center.togglePlayPauseCommand, 2), (center.stopCommand, 3)] {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.player.currentItem != nil else { return }
                    if action == 0 { self.player.play() }
                    else if action == 1 { self.pause() }
                    else if action == 2 { self.togglePlayPause() }
                    else if let onRemoteStop = self.onRemoteStop { onRemoteStop() }
                    else { self.stop() }
                }
                return .success
            }
            remoteTargets.append((command, target))
        }
    }

    private func fail(_ message: String, reason: DiagnosticReason, failure: DiagnosticFailure? = nil) {
        stop()
        errorMessage = message
        state = .failed
        onFailure?(message)
        var values = DiagnosticValues()
        values.reason = reason
        values.failure = failure
        onDiagnostic?(.failure, values)
    }

    private func recordAudioRoute() {
        var values = DiagnosticValues()
        values.audioRoutes = AVAudioSession.sharedInstance().currentRoute.outputs.map {
            switch $0.portType {
            case .carAudio: return .car
            case .airPlay: return .airPlay
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return .bluetooth
            case .builtInSpeaker, .builtInReceiver: return .speaker
            case .headphones: return .headphones
            default: return .other
            }
        }
        onDiagnostic?(.audioRouteChanged, values)
    }
}
