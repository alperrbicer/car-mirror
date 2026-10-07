import AVFoundation
import AVKit
import Combine
import MediaPlayer
@preconcurrency import GoogleCast

@MainActor
final class PlaybackController: ObservableObject {
    enum State { case idle, loading, playing, paused, failed }
    let player = AVPlayer()
    @Published private(set) var compatibility: CompatibilityPlayback?
    @Published private(set) var tvDevice: GCKDevice?
    var tvName: String? { tvDevice.map { $0.friendlyName ?? $0.modelName ?? "Google Cast" } }
    private var casting: CastPlayback?
    private var personalMediaServer: PersonalMediaServer?
    private var localCastAwakeLease: UUID?
    private struct Request {
        let url: URL
        let preserveSourceAudio: Bool
        let muted: Bool
        let requiresExternalPlayback: Bool
        let title: String?
        let live: Bool
        let presentation: MediaPlaybackPresentation
        let useCompatibility: Bool
    }
    private var request: Request?
    private var nativeResumePosition: Double?
    private var restoringCompatibilityPosition = false
    @Published var externalDisplayConnected = false
    private var pauseOnStart = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isLive = false
    @Published private(set) var canSeek = false
    private var timeObserver: Any?
    private var durationObservation: NSKeyValueObservation?
    private var pendingSeek: UUID?
    private var requestedLive = false
    var onRestorePlayer: ((@escaping (Bool) -> Void) -> Void)?
    // Keep the source layer and its delegate alive while PiP owns the video.
    var retainedPiPController: UIViewController?
    weak var nativePiP: AVPictureInPictureController?
    private(set) var pendingAutomaticPiP = false
    private var startingPiP = false
    private var enteredBackgroundWithVideo = false
    private var restorePiPOnStart = false
    private var foregroundPiPRestoreID: UUID?
    private var currentNativePiP: AVPictureInPictureController? {
        (retainedPiPController as? NativeVideoController)?.pip ?? nativePiP
    }
    var canStartPictureInPicture: Bool {
        hasActivePlayback && request?.presentation == .video && tvDevice == nil && !externalPlaybackActive && !externalDisplayConnected &&
        (compatibility?.pip != nil || currentNativePiP?.isPictureInPicturePossible == true)
    }
    func startPictureInPicture() {
        guard canStartPictureInPicture else { return }
        if let compatibility {
            if compatibility.pipActive { pictureInPictureStarted() }
            else if !startingPiP {
                startingPiP = true
                compatibility.pip?.startPictureInPicture()
            }
        } else if let pip = currentNativePiP {
            if pip.isPictureInPictureActive || (retainedPiPController as? NativeVideoController)?.startingPiP == true { pictureInPictureStarted() }
            else if !startingPiP { startingPiP = true; pip.startPictureInPicture() }
        }
    }
    func startPendingPictureInPicture() {
        guard pendingAutomaticPiP else { return }
        startPictureInPicture()
    }
    func pictureInPictureStarted() {
        startingPiP = false
        pendingAutomaticPiP = false
        if restorePiPOnStart { restorePictureInPictureToApp() }
    }
    func pictureInPictureStopped() {
        startingPiP = false
        pendingAutomaticPiP = false
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
    }
    func applicationDidEnterBackground() {
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
        enteredBackgroundWithVideo = false
        guard hasActivePlayback, request?.presentation == .video, tvDevice == nil,
              !externalPlaybackActive, !externalDisplayConnected else { return }
        enteredBackgroundWithVideo = true
        pendingAutomaticPiP = true
        startPendingPictureInPicture()
    }
    func applicationDidBecomeActive() {
        guard enteredBackgroundWithVideo else { return }
        enteredBackgroundWithVideo = false
        // AVKit doesn't stop PiP when the user returns via the app icon.
        // Keep the existing player screen (and its full-screen state), restore
        // it before stopping PiP, and handle a start that is still in flight.
        restorePiPOnStart = startingPiP || compatibility?.pipActive == true ||
            currentNativePiP?.isPictureInPictureActive == true ||
            (retainedPiPController as? NativeVideoController)?.startingPiP == true
        pendingAutomaticPiP = false
        if restorePiPOnStart { restorePictureInPictureToApp() }
    }
    private func restorePictureInPictureToApp() {
        let engine = compatibility
        let pip = currentNativePiP
        guard engine?.pipActive == true || (pip?.isPictureInPictureActive == true &&
            (retainedPiPController as? NativeVideoController)?.startingPiP != true),
            foregroundPiPRestoreID == nil else { return }
        let id = UUID()
        foregroundPiPRestoreID = id
        let finish: (Bool) -> Void = { [weak self, weak engine, weak pip] restored in
            guard let self, self.foregroundPiPRestoreID == id else { return }
            self.foregroundPiPRestoreID = nil
            self.restorePiPOnStart = false
            guard restored else { return }
            if let engine, self.compatibility === engine {
                engine.pip?.stopPictureInPicture()
            } else if let pip, self.compatibility == nil, self.currentNativePiP === pip {
                pip.stopPictureInPicture()
            }
        }
        if let restore = onRestorePlayer { restore(finish) }
        else { finish(true) }
    }
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
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applicationDidEnterBackground() }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applicationDidBecomeActive() }
            })
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
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
                guard let self, self.compatibility == nil, self.casting == nil else { return }
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
                    guard let self, self.casting == nil else { return }
                    var values = DiagnosticValues()
                    values.reason = .interrupted
                    self.onDiagnostic?(.audioInterrupted, values)
                    if began {
                        self.wasPlayingBeforeInterruption = self.isPlaying
                        self.interruptionItem = self.player.currentItem
                        if let compatibility = self.compatibility { compatibility.pause() } else { self.player.pause() }
                    } else {
                        let flags = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                        if flags & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0,
                           self.wasPlayingBeforeInterruption, self.player.currentItem === self.interruptionItem {
                            try? AVAudioSession.sharedInstance().setActive(true)
                            self.resume()
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

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func play(url: URL, preserveSourceAudio: Bool = true, muted: Bool = false,
              requiresExternalPlayback: Bool = true, title: String? = nil, live: Bool = true,
              presentation: MediaPlaybackPresentation = .video, useCompatibility: Bool = false,
              startAt: Double = 0, startPaused: Bool = false) throws {
        stop()
        request = Request(url: url, preserveSourceAudio: preserveSourceAudio, muted: muted,
                          requiresExternalPlayback: requiresExternalPlayback, title: title, live: live,
                          presentation: presentation, useCompatibility: useCompatibility)
        let position = startAt.isFinite ? max(0, startAt) : 0
        currentTime = position
        pauseOnStart = startPaused
        requestedLive = live
        isLive = live
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
        waitingForExternalPlayback = requiresExternalPlayback && presentation == .video && tvDevice == nil
        player.isMuted = muted
        player.allowsExternalPlayback = presentation == .video
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title ?? L10n.tr("iPhone ekranı"),
            MPMediaItemPropertyArtist: BrandIdentity.name,
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyMediaType: presentation == .audio ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0
        ]
        if let device = tvDevice {
            let cast = CastPlayback()
            casting = cast
            state = .loading
            cast.onState = { [weak self, weak cast] state in
                guard let self, let cast, self.casting === cast else { return }
                if state == .failed {
                    self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .playback)
                    return
                }
                self.state = state
                self.isPlaying = state == .playing
                if state == .playing || state == .paused {
                    self.pauseOnStart = state == .paused
                    self.startupTask?.cancel(); self.startupTask = nil
                }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
            }
            cast.onTime = { [weak self, weak cast] time, length, seekable, live in
                guard let self, let cast, self.casting === cast, self.pendingSeek == nil else { return }
                self.updateTimeline(time: time, length: length, seekable: seekable, live: live)
                self.isLive = live
            }
            cast.onFinished = { [weak self, weak cast] in
                guard let self, let cast, self.casting === cast else { return }
                self.stop(); self.onFinished?()
            }
            if url.isFileURL {
                let server = try PersonalMediaServer(file: url)
                personalMediaServer = server
                localCastAwakeLease = MediaScreenAwake.acquire()
                server.start(onReady: { [weak self, weak cast] address in
                    Task { @MainActor in
                        guard let self, let cast, self.casting === cast else { return }
                        cast.open(url: address, device: device, title: title, live: false, startAt: position, paused: startPaused)
                    }
                }, onFailure: { [weak self, weak cast] in
                    Task { @MainActor in
                        guard let self, let cast, self.casting === cast else { return }
                        self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .unavailable)
                    }
                })
            } else {
                cast.open(url: url, device: device, title: title, live: live, startAt: position, paused: startPaused)
            }
            guard casting === cast else { return }
            installRemoteCommands()
            startupTask = Task { [weak self, weak cast] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, let cast, self.casting === cast, self.state == .loading else { return }
                self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .unavailable)
            }
            return
        }
        if useCompatibility {
            let engine = CompatibilityPlayback()
            compatibility = engine
            engine.onPiPReady = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.startPendingPictureInPicture()
            }
            engine.onPiPStarted = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.pictureInPictureStarted()
            }
            engine.onPiPStopped = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.pictureInPictureStopped()
            }
            state = .loading
            var resumePosition: Double? = position > 0 ? position : nil
            engine.onState = { [weak self, weak engine] state in
                guard let self, let engine, self.compatibility === engine else { return }
                if state == .failed {
                    self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .playback)
                    return
                }
                if state == .playing, let position = resumePosition {
                    resumePosition = nil
                    self.restoreCompatibilityPosition(position, engine: engine)
                    return
                }
                if self.restoringCompatibilityPosition { return }
                if state == .playing, self.pauseOnStart {
                    self.pauseOnStart = false
                    self.startupTask?.cancel(); self.startupTask = nil
                    engine.pause()
                    self.state = .paused
                    self.isPlaying = false
                    return
                }
                self.state = state
                self.isPlaying = state == .playing
                if self.isPlaying { self.startupTask?.cancel(); self.startupTask = nil }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
            }
            engine.onTime = { [weak self, weak engine] time, length in
                guard let self, let engine, self.compatibility === engine, self.pendingSeek == nil, resumePosition == nil else { return }
                self.updateTimeline(time: time, length: length, seekable: engine.isMediaSeekable(), live: self.requestedLive)
            }
            engine.onFinished = { [weak self, weak engine] in
                guard let self, let engine, self.compatibility === engine else { return }
                self.stop(); self.onFinished?()
            }
            engine.onRestore = { [weak self] in self?.onRestorePlayer?({ _ in }) }
            engine.open(url)
            installRemoteCommands(); recordAudioRoute()
            startupTask = Task { [weak self, weak engine] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, let engine, self.compatibility === engine, !self.isPlaying else { return }
                self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .unavailable)
            }
            return
        }
        let item = AVPlayerItem(url: url)
        nativeResumePosition = position > 0 || startPaused ? position : nil
        item.preferredForwardBufferDuration = 2
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."),
                              reason: .playback, failure: item.error.map(DiagnosticFailure.init))
                } else if item.status == .readyToPlay, let position = self.nativeResumePosition {
                    self.nativeResumePosition = nil
                    self.player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] _ in
                        Task { @MainActor in
                            guard let self, let item, self.player.currentItem === item else { return }
                            if self.pauseOnStart { self.pauseOnStart = false; self.pause() }
                            else { self.player.play() }
                        }
                    }
                } else { self.refreshNativeTimeline(item) }
            }
        }
        state = .loading
        player.replaceCurrentItem(with: item)
        durationObservation = item.observe(\.duration, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item else { return }
                self.refreshNativeTimeline(item)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item else { return }
                self.refreshNativeTimeline(item)
            }
        }
        if nativeResumePosition == nil { player.play() }
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
        pendingAutomaticPiP = false
        startingPiP = false
        enteredBackgroundWithVideo = false
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
        currentNativePiP?.stopPictureInPicture()
        personalMediaServer?.stop(); personalMediaServer = nil
        MediaScreenAwake.release(localCastAwakeLease); localCastAwakeLease = nil
        request = nil
        nativeResumePosition = nil
        restoringCompatibilityPosition = false
        pauseOnStart = false
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        durationObservation = nil
        pendingSeek = nil
        casting?.stop(); casting = nil
        compatibility?.stop()
        compatibility = nil
        currentTime = 0; duration = 0
        canSeek = false; isLive = false; requestedLive = false
        startupTask?.cancel()
        startupTask = nil
        waitingForExternalPlayback = false
        stallTask?.cancel(); stallTask = nil
        interruptionItem = nil
        wasPlayingBeforeInterruption = false
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

    private func restoreCompatibilityPosition(_ position: Double, engine: CompatibilityPlayback) {
        // VLC's start-time input option may jump to a later keyframe. Restore
        // with the same accurate seek path used by the timeline, after opening.
        restoringCompatibilityPosition = true
        let stayPaused = pauseOnStart
        pauseOnStart = false
        let seekID = UUID()
        pendingSeek = seekID
        currentTime = position
        engine.pause()
        engine.seek(to: position) { [weak self, weak engine] in
            guard let self, let engine, self.compatibility === engine, self.pendingSeek == seekID else { return }
            self.pendingSeek = nil
            self.restoringCompatibilityPosition = false
            self.updateTimeline(time: Double(engine.mediaTime()) / 1000, length: Double(engine.mediaLength()) / 1000,
                                seekable: engine.isMediaSeekable(), live: self.requestedLive)
            if stayPaused {
                self.startupTask?.cancel(); self.startupTask = nil
                self.state = .paused
                self.isPlaying = false
            } else { engine.play() }
        }
    }

    /// Keep the selected destination across channel changes. Stop clears media;
    /// disconnect clears the destination and restores the phone's usual engine.
    func setTVDevice(_ device: GCKDevice?) throws {
        if let device, tvDevice?.isSameDevice(as: device) == true { return }
        guard tvDevice != nil || device != nil else { return }
        let previous = request
        let position = isLive ? 0 : currentTime
        let live = isLive
        let paused = state == .paused || pauseOnStart
        tvDevice = device
        if device == nil { casting?.stop(); CastPlayback.disconnect() }
        guard let previous, hasActivePlayback || state == .failed else { return }
        try play(url: previous.url, preserveSourceAudio: previous.preserveSourceAudio, muted: previous.muted,
                 requiresExternalPlayback: device == nil && previous.requiresExternalPlayback,
                 title: previous.title, live: live, presentation: previous.presentation,
                 useCompatibility: previous.useCompatibility, startAt: position, startPaused: paused)
    }

    func togglePlayPause() {
        guard hasActivePlayback else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        pauseOnStart = false
        if let casting { casting.play() }
        else if let compatibility { compatibility.play() } else if player.currentItem != nil { player.play() }
    }

    func seek(to seconds: Double) {
        guard hasActivePlayback, canSeek, seconds.isFinite else { return }
        let target = min(max(0, seconds), duration)
        let request = UUID()
        pendingSeek = request
        currentTime = target
        if let casting {
            casting.seek(to: target) { [weak self, weak casting] in
                guard let self, let casting, self.casting === casting, self.pendingSeek == request else { return }
                self.pendingSeek = nil
            }
        } else if let engine = compatibility {
            engine.seek(to: target) { [weak self, weak engine] in
                Task { @MainActor in
                    guard let self, let engine, self.compatibility === engine, self.pendingSeek == request else { return }
                    self.pendingSeek = nil
                    self.updateTimeline(time: Double(engine.mediaTime()) / 1000, length: Double(engine.mediaLength()) / 1000,
                                        seekable: engine.isMediaSeekable(), live: self.requestedLive)
                }
            }
        } else if let item = player.currentItem {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] _ in
                Task { @MainActor in
                    guard let self, let item, self.player.currentItem === item, self.pendingSeek == request else { return }
                    self.pendingSeek = nil
                    self.refreshNativeTimeline(item)
                }
            }
        }
    }

    private func refreshNativeTimeline(_ item: AVPlayerItem) {
        guard player.currentItem === item, compatibility == nil, casting == nil, pendingSeek == nil, nativeResumePosition == nil else { return }
        let seekable = item.status == .readyToPlay && item.seekableTimeRanges.contains {
            let length = $0.timeRangeValue.duration.seconds
            return length.isFinite && length > 0
        }
        updateTimeline(time: player.currentTime().seconds, length: item.duration.seconds,
                       seekable: seekable, live: item.duration.isIndefinite || requestedLive)
    }

    private func updateTimeline(time: Double, length: Double, seekable: Bool, live: Bool) {
        duration = length.isFinite && length > 0 ? length : 0
        currentTime = time.isFinite ? max(0, duration > 0 ? min(time, duration) : time) : 0
        // A finite duration also identifies VOD served as an HLS or extensionless URL.
        isLive = duration > 0 ? false : live
        canSeek = duration > 0 && seekable
        guard var metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        metadata[MPNowPlayingInfoPropertyIsLiveStream] = isLive
        if duration > 0 { metadata[MPMediaItemPropertyPlaybackDuration] = duration }
        else { metadata.removeValue(forKey: MPMediaItemPropertyPlaybackDuration) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
    }

    private func pause() {
        wasPlayingBeforeInterruption = false
        startupTask?.cancel(); startupTask = nil
        if let casting { casting.pause() }
        else if let compatibility { compatibility.pause() } else { player.pause() }
        state = .paused
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        for (command, action) in [(center.playCommand, 0), (center.pauseCommand, 1), (center.togglePlayPauseCommand, 2), (center.stopCommand, 3)] {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.hasActivePlayback else { return }
                    if action == 0 { self.resume() }
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
        let retry = request
        let position = currentTime
        let live = isLive
        let paused = state == .paused || pauseOnStart
        stop()
        request = retry
        currentTime = position
        isLive = live
        pauseOnStart = paused
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
