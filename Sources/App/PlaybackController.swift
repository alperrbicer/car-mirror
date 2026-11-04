import AVFoundation
import AVKit
import Combine
import MediaPlayer
@preconcurrency import GoogleCast

struct PlaybackTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let isSelected: Bool
}

struct PlaybackVideoQuality: Identifiable, Equatable {
    let resolution: CGSize
    var id: String { "\(Int(resolution.width))x\(Int(resolution.height))" }
    var title: String { "\(Int(min(resolution.width, resolution.height)))p" }
}

enum PlayerSubtitlePosition: String, CaseIterable, Identifiable {
    case provider, raised, higher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .provider: "Varsayılan"
        case .raised: "Biraz yukarı"
        case .higher: "Daha yukarı"
        }
    }
    var linePosition: Int? {
        switch self {
        case .provider: nil
        case .raised: 85
        case .higher: 75
        }
    }
}

@MainActor
final class PlaybackController: ObservableObject {
    enum State { case idle, loading, playing, paused, failed }
    let player = AVPlayer()
    @Published private(set) var compatibility: CompatibilityPlayback?
    @Published private(set) var tvDevice: GCKDevice?
    var tvName: String? { tvDevice.map { $0.friendlyName ?? $0.modelName ?? "Google Cast" } }
    private var casting: CastPlayback?
    private var personalMediaServer: PersonalMediaServer?
    private var mediaRelay: MediaRelayServer?
    private var carPlayBridge: CarPlayHLSBridge?
    private var liveSourcePreparation: Task<Void, Never>?
    private var bridgeTimeOrigin: Double?
    private var externalPlaybackLossTask: Task<Void, Never>?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    @Published private var continuingRemoteVideo = false
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
        let lowLatency: Bool
        let artworkURL: URL?
    }
    private var request: Request?
    private var nativeResumePosition: Double?
    private weak var carPlayPrerollItem: AVPlayerItem?
    private var carPlayPrerollPending = false
    private var carPlayPrerollReady = false
    private var preparingCarPlayVideo = false
    private var restoringCompatibilityPosition = false
    @Published var externalDisplayConnected = false {
        didSet { updateVideoOutput() }
    }
    @Published private(set) var playsOnPhone = false
    @Published private(set) var carPlayConnected = false
    private var carPlayVideoSupported = false
    @Published private(set) var externalTVDisplayConnected = false
    @Published private(set) var airPlayName = AVAudioSession.sharedInstance().currentRoute.outputs.first { $0.portType == .airPlay }?.portName
    var displayConnection: DisplayConnection {
        DisplayConnection(routes: ConnectedDisplayRoute.resolve(cast: tvDevice != nil, carPlay: carPlayConnected,
            externalDisplay: externalTVDisplayConnected || (externalDisplayConnected && !carPlayConnected),
            externalPlayback: externalPlaybackActive, airPlayAudio: airPlayName != nil),
            castName: tvName, airPlayName: airPlayName)
    }
    private var outputPolicy: VideoOutputPolicy {
        VideoOutputPolicy(video: request?.presentation == .video, phone: playsOnPhone,
            carPlay: carPlayConnected, supportsVideo: carPlayVideoSupported,
            externalDisplay: externalDisplayConnected, externalTV: externalTVDisplayConnected, cast: tvDevice != nil)
    }
    var usesSystemCarPlayVideo: Bool { outputPolicy.systemCarPlay }
    var usesOwnedVideoDisplay: Bool { outputPolicy.ownedDisplay }
    var hasRemoteVideoOutput: Bool { !playsOnPhone && (tvDevice != nil || usesOwnedVideoDisplay || externalPlaybackActive || continuingRemoteVideo) }
    // A receiver that loads the URL itself owns its sizing. App-owned CarPlay,
    // HDMI and AirPlay display windows use our video renderer and can be sized.
    var canAdjustRemoteVideoDisplayMode: Bool { usesOwnedVideoDisplay && tvDevice == nil }

    /// Keep the timeline when a system video route requires a different decoder.
    func setPlaysOnPhone(_ value: Bool) {
        guard playsOnPhone != value else { return }
        let previousSystemRoute = usesSystemCarPlayVideo
        playsOnPhone = value
        updateVideoOutput()
        reconcileVideoDecoder(previousSystemRoute: previousSystemRoute)
    }

    private func updateVideoOutput() {
        if !usesSystemCarPlayVideo { preparingCarPlayVideo = false }
        // A CarPlay receiver must remain eligible even if iOS also supplies a
        // scene. Only an app-owned TV/HDMI output should suppress AirPlay video.
        let externalVideo = outputPolicy.allowsExternalPlayback && !preparingCarPlayVideo
        let systemVideo = usesSystemCarPlayVideo && !preparingCarPlayVideo
        if player.usesExternalPlaybackWhileExternalScreenIsActive != systemVideo {
            player.usesExternalPlaybackWhileExternalScreenIsActive = systemVideo
        }
        if player.allowsExternalPlayback != externalVideo {
            player.allowsExternalPlayback = externalVideo
        }
        compatibility?.setExternalVideoEnabled(!playsOnPhone)
        if usesOwnedVideoDisplay || playsOnPhone { waitingForExternalPlayback = false }
    }

    private func reconcileVideoDecoder(previousSystemRoute: Bool) {
        guard previousSystemRoute != usesSystemCarPlayVideo, hasActivePlayback, let request,
              request.presentation == .video else { return }
        // Native HLS/relay playback can move back to the phone without opening
        // the source again. Recreating it also recreates the system route prompt.
        let needsRestart = (usesSystemCarPlayVideo && compatibility != nil) ||
            (usesSystemCarPlayVideo && carPlayBridge == nil && MediaChannel(title: "", url: request.url).requiresCompatibilityPlayback) ||
            (usesSystemCarPlayVideo && request.url.isFileURL && personalMediaServer == nil && carPlayBridge == nil)
        guard needsRestart else { return }
        let position = request.live ? 0 : currentTime
        let paused = pauseRequested || state == .paused
        do {
            try play(url: request.url, preserveSourceAudio: request.preserveSourceAudio, muted: request.muted,
                requiresExternalPlayback: request.requiresExternalPlayback, title: request.title, live: request.live,
                presentation: request.presentation, useCompatibility: request.useCompatibility,
                startAt: position, startPaused: paused, lowLatency: request.lowLatency, artworkURL: request.artworkURL)
        } catch { fail(displayConnection.failureMessage, reason: .preparation, failure: DiagnosticFailure(error)) }
    }
    @Published private(set) var screenCaptureBlocked = false
    private var broadcastCaptureActive = false
    private var shouldBlockCapturedPlayback: Bool {
        screenCaptureBlocked && !hasRemoteVideoOutput && request?.presentation == .video
    }

    func setScreenCaptureBlocked(_ blocked: Bool) {
        guard screenCaptureBlocked != blocked else { return }
        screenCaptureBlocked = blocked
        if shouldBlockCapturedPlayback && hasActivePlayback { pause() }
    }

    func setBroadcastCaptureActive(_ active: Bool) {
        guard broadcastCaptureActive != active else { return }
        broadcastCaptureActive = active
        compatibility?.setBroadcastCaptureActive(active)
    }

    func displayPlaybackStatus(for route: ConnectedDisplayRoute? = nil) -> String {
        displayConnection.playbackStatus(hasRemoteVideoOutput ? state : .idle, for: route)
    }

    func updateConnectedDisplays(carPlay: Bool, externalTV: Bool, supportsCarPlayVideo: Bool = false) {
        let previousSystemRoute = usesSystemCarPlayVideo
        carPlayConnected = carPlay
        carPlayVideoSupported = carPlay && supportsCarPlayVideo
        externalTVDisplayConnected = externalTV
        updateVideoOutput()
        reconcileVideoDecoder(previousSystemRoute: previousSystemRoute)
        updateRemoteSeekCommands()
    }

    private var pauseRequested = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isLive = false
    @Published private(set) var canSeek = false {
        didSet { updateRemoteSeekCommands() }
    }
    @Published private(set) var audioTracks: [PlaybackTrack] = []
    @Published private(set) var subtitleTracks: [PlaybackTrack] = []
    @Published private(set) var canDisableSubtitles = false
    @Published private(set) var videoQualities: [PlaybackVideoQuality] = []
    @Published private(set) var selectedVideoQualityID: String?
    var showsVideoQuality: Bool {
        request?.presentation == .video && !isLive && tvDevice == nil && compatibility == nil && videoQualities.count > 1
    }
    @Published var subtitlePosition = PlayerSubtitlePosition(rawValue: UserDefaults.standard.string(forKey: "player.subtitlePosition") ?? "") ?? .provider {
        didSet {
            UserDefaults.standard.set(subtitlePosition.rawValue, forKey: "player.subtitlePosition")
            if let item = player.currentItem { applySubtitlePosition(to: item) }
        }
    }
    var canAdjustSubtitlePosition: Bool { compatibility == nil && tvDevice == nil && !subtitleTracks.isEmpty }
    private func applySubtitlePosition(to item: AVPlayerItem) {
        guard let position = subtitlePosition.linePosition,
              let rule = AVTextStyleRule(textMarkupAttributes: [
                kCMTextMarkupAttribute_OrthogonalLinePositionPercentageRelativeToWritingDirection as String: position
              ]) else { item.textStyleRules = nil; return }
        item.textStyleRules = [rule]
    }
    var hasMediaChoices: Bool { audioTracks.count > 1 || !subtitleTracks.isEmpty || videoQualities.count > 1 }
    private var audioGroup: AVMediaSelectionGroup?
    private var subtitleGroup: AVMediaSelectionGroup?
    private var nativeAudioOptions: [AVMediaSelectionOption] = []
    private var nativeSubtitleOptions: [AVMediaSelectionOption] = []
    private var trackLoadingTask: Task<Void, Never>?
    private var qualityLoadingTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var durationObservation: NSKeyValueObservation?
    private var pendingSeek: UUID?
    private var requestedLive = false
    var onRestorePlayer: ((@escaping (Bool) -> Void) -> Void)?
    // Keep the source layer and its delegate alive while PiP owns the video.
    var retainedPiPController: UIViewController?
    weak var nativePiP: AVPictureInPictureController?
    private(set) var playbackID = UUID()
    private(set) var pendingAutomaticPiP = false
    @Published private var startingPiP = false
    @Published private var stoppingPiP = false
    private var retiringPiPSources: Set<ObjectIdentifier> = []
    private var enteredBackgroundWithVideo = false
    private var restorePiPOnStart = false
    private var foregroundPiPRestoreID: UUID?
    private var foregroundPiPRestoreTask: Task<Void, Never>?
    private var currentNativePiP: AVPictureInPictureController? {
        (retainedPiPController as? NativeVideoController)?.pip ?? nativePiP
    }
    var pictureInPictureActiveOrStarting: Bool {
        if let compatibility { return compatibility.pipActive || compatibility.pipStarting }
        return currentNativePiP?.isPictureInPictureActive == true ||
            (retainedPiPController as? NativeVideoController)?.startingPiP == true
    }
    var canStartPictureInPicture: Bool {
        guard hasActivePlayback, !screenCaptureBlocked, request?.presentation == .video, tvDevice == nil,
              !hasRemoteVideoOutput,
              retiringPiPSources.isEmpty, !startingPiP, !stoppingPiP, !pictureInPictureActiveOrStarting else { return false }
        // Only the decoder currently rendering the video can supply its PiP source.
        if let compatibility { return compatibility.pipPossible }
        return currentNativePiP?.isPictureInPicturePossible == true &&
            (currentNativePiP?.delegate as? NativeVideoController)?.stoppingForPlaybackReplacement != true
    }
    func pictureInPictureAvailabilityChanged() {
        // AVKit readiness isn't a @Published property. Notify the controls even
        // when playback is paused and no timeline update will redraw them.
        objectWillChange.send()
        startPendingPictureInPicture()
    }
    func nativePictureInPictureAvailabilityChanged(_ controller: AVPictureInPictureController) {
        guard compatibility == nil, currentNativePiP === controller else { return }
        pictureInPictureAvailabilityChanged()
    }
    func nativeVideoOutputReadinessChanged(for item: AVPlayerItem, ready: Bool) {
        guard ready, request?.presentation == .video, compatibility == nil,
              player.currentItem === item,
              item.presentationSize.width > 0, item.presentationSize.height > 0,
              !videoReadyForDisplay else { return }
        videoReadyForDisplay = true
    }
    func startPictureInPicture() {
        // A request during the return animation is rejected by AVKit. Do not
        // latch startingPiP for a request that was never sent.
        guard !stoppingPiP else { return }
        // An automatic background request can arrive while PiP is already
        // running. Consume it without launching again or leaving it pending.
        let alreadyActive = compatibility.map { $0.pipActive } ?? (currentNativePiP?.isPictureInPictureActive == true)
        if alreadyActive {
            pictureInPictureStarted()
            return
        }
        guard canStartPictureInPicture else { return }
        if let compatibility {
            startingPiP = true
            if !compatibility.startPictureInPicture() { startingPiP = false }
        } else if let pip = currentNativePiP {
            startingPiP = true
            (pip.delegate as? NativeVideoController)?.preparePictureInPictureRequest()
            pip.startPictureInPicture()
        }
    }
    func startPendingPictureInPicture() {
        guard pendingAutomaticPiP else { return }
        startPictureInPicture()
    }
    #if DEBUG
    // An in-app probe exercises public PiP APIs without driving SpringBoard.
    // It deliberately keeps the app visible to isolate the video handoff from
    // the separate system app-opening animation.
    func runPictureInPictureProbe() async {
        for _ in 0..<300 {
            if isPlaying && canStartPictureInPicture { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard isPlaying, canStartPictureInPicture else { return }
        for _ in 0..<2 {
            startPictureInPicture()
            for _ in 0..<50 {
                if compatibility?.pipActive == true || currentNativePiP?.isPictureInPictureActive == true { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(3))
            restorePictureInPictureToApp()
            try? await Task.sleep(for: .seconds(4))
        }
    }
    #endif
    func pictureInPictureStarted() {
        startingPiP = false
        pendingAutomaticPiP = false
        if restorePiPOnStart { restorePictureInPictureToApp() }
    }
    func pictureInPictureWillStop() {
        foregroundPiPRestoreTask?.cancel(); foregroundPiPRestoreTask = nil
        stoppingPiP = true
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
    }
    func pictureInPictureStopped() {
        foregroundPiPRestoreTask?.cancel(); foregroundPiPRestoreTask = nil
        startingPiP = false
        stoppingPiP = false
        pendingAutomaticPiP = false
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
    }
    func pictureInPictureSourceStopped(_ source: AnyObject) {
        guard retiringPiPSources.remove(ObjectIdentifier(source)) != nil else { return }
        // A replacement decoder can become ready before AVKit finishes closing
        // the previous window. Start it only after that handoff has completed.
        startPendingPictureInPicture()
        objectWillChange.send()
    }
    func applicationDidEnterBackground() {
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
        enteredBackgroundWithVideo = false
        guard hasActivePlayback, request?.presentation == .video, tvDevice == nil,
              !hasRemoteVideoOutput else { return }
        enteredBackgroundWithVideo = true
        pendingAutomaticPiP = true
        startPendingPictureInPicture()
    }
    func applicationDidBecomeActive() {
        let returningFromBackground = enteredBackgroundWithVideo
        enteredBackgroundWithVideo = false
        // Alerts and system overlays also reactivate the app. They must not
        // close PiP that the user explicitly opened while the app was visible.
        guard returningFromBackground else { return }
        // The PiP return button already owns this stop. Sending another one
        // during activation interrupts the system's return to the inline view.
        guard !stoppingPiP else { return }
        // AVKit can leave PiP floating when the user reopens the app directly.
        // Restore the existing player before stopping PiP, including a start
        // that was still in flight as the app became active.
        restorePiPOnStart = startingPiP || pictureInPictureActiveOrStarting
        pendingAutomaticPiP = false
        foregroundPiPRestoreTask?.cancel(); foregroundPiPRestoreTask = nil
        if restorePiPOnStart {
            restorePictureInPictureToApp()
            // AVKit may finish its automatic start after UIApplication becomes
            // active. Recheck once the activation transition has settled.
            let id = playbackID
            foregroundPiPRestoreTask = Task { @MainActor [weak self] in
                // The first layout preparation can time out during the app
                // opening animation. Retry after it, not just while it is pending.
                for _ in 0..<6 {
                    do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                    guard let self, self.playbackID == id,
                          UIApplication.shared.applicationState == .active,
                          self.pictureInPictureActiveOrStarting, !self.stoppingPiP else { return }
                    self.restorePiPOnStart = true
                    self.restorePictureInPictureToApp()
                }
            }
        }
    }
    func applicationWillEnterForeground() {
        guard enteredBackgroundWithVideo else { return }
        // Settle the source's layout without overwriting AVKit's in-flight
        // corner animation. Clipping cleanup belongs to didStop only.
        prepareVideoForPictureInPictureReturn()
    }
    private func prepareVideoForPictureInPictureReturn() {
        if let compatibility { compatibility.layoutVideoForPictureInPictureReturn() }
        else if let controller = retainedPiPController as? NativeVideoController { controller.layoutVideoForPictureInPictureReturn() }
        else if let layer = currentNativePiP?.playerLayer {
            // A PiP source may still be alive through a mounted inline view.
            // Its controller normally owns the repair policy.
            layer.setNeedsLayout()
            layer.layoutIfNeeded()
        }
    }
    func restoreUserInterfaceForPictureInPictureStop(completion: @escaping (Bool) -> Void) {
        pictureInPictureWillStop()
        restorePlayerInterface { [weak self] restored in
            if !restored { self?.stoppingPiP = false }
            completion(restored)
        }
    }
    private func restorePlayerInterface(completion: @escaping (Bool) -> Void) {
        let engine = compatibility
        let usesCompatibility = engine != nil
        let controller = retainedPiPController as? NativeVideoController
        let item = player.currentItem
        let prepared: (Bool) -> Void = { [weak self, weak engine, weak controller] restored in
            guard let self, restored, self.hasActivePlayback else { completion(false); return }
            let sameSource = usesCompatibility ? engine != nil && self.compatibility === engine :
                controller != nil && self.compatibility == nil &&
                self.retainedPiPController === controller && self.player.currentItem === item
            completion(sameSource)
        }
        let finish: (Bool) -> Void = { [weak self, weak engine, weak controller] restored in
            guard let self, restored, self.hasActivePlayback else { completion(false); return }
            if let engine, self.compatibility === engine {
                engine.preparePictureInPictureReturn(completion: prepared)
            } else if let controller, self.retainedPiPController === controller {
                controller.preparePictureInPictureReturn(completion: prepared)
            } else { completion(false) }
        }
        if let restore = onRestorePlayer { restore(finish) }
        else { finish(true) }
    }
    private func restorePictureInPictureToApp() {
        let engine = compatibility
        let pip = currentNativePiP
        guard !stoppingPiP, engine?.pipActive == true || (pip?.isPictureInPictureActive == true &&
            (retainedPiPController as? NativeVideoController)?.startingPiP != true),
            foregroundPiPRestoreID == nil else { return }
        let id = UUID()
        foregroundPiPRestoreID = id
        let finish: (Bool) -> Void = { [weak self, weak engine, weak pip] restored in
            guard let self, self.foregroundPiPRestoreID == id else { return }
            self.foregroundPiPRestoreID = nil
            self.restorePiPOnStart = false
            guard restored else { return }
            self.stoppingPiP = true
            if let engine, self.compatibility === engine {
                engine.pip?.stopPictureInPicture()
            } else if let pip, self.compatibility == nil, self.currentNativePiP === pip {
                pip.stopPictureInPicture()
            }
        }
        restorePlayerInterface(completion: finish)
    }
    @Published private(set) var state: State = .idle {
        didSet {
            measurement.playing(state == .playing)
            updateRemoteTrackCommands()
            updateRemoteSeekCommands()
        }
    }
    /// True after the current native/VLC video renderer has a decoded frame.
    /// The inline player uses this to prevent a fullscreen transition from
    /// animating an uninitialized video rectangle during startup.
    @Published private(set) var videoReadyForDisplay = false
    private let measurement = PlaybackMeasurement()
    var hasActivePlayback: Bool { state == .loading || state == .playing || state == .paused }
    var canUseVehicleMode: Bool { state == .playing || state == .paused }
    @Published private(set) var externalPlaybackActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private var externalObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var playingObservation: NSKeyValueObservation?
    private var activatedAudioSession = false
    private var pendingCarPlayResume: (() -> Void)?
    private var waitingForExternalPlayback = false
    var onDiagnostic: ((DiagnosticKind, DiagnosticValues) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onRemoteStop: (() -> Void)?
    var remoteTrackAvailability: (() -> (previous: Bool, next: Bool))?
    var onRemoteTrackChange: ((Int) -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []
    private var startupTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var liveRecoveryTask: Task<Void, Never>?
    private var liveRecoveryAttempt = 0
    private var interruptedPlaybackID: UUID?
    private var resumeAfterInterruption = false
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init() {
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationWillEnterForeground() }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                // PiP must be requested while the app still has an execution
                // window. Enqueuing a MainActor task here can let iOS suspend
                // the app before the compatibility renderer receives it.
                MainActor.assumeIsolated { self?.applicationDidEnterBackground() }
            })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationDidBecomeActive() }
            })
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
        player.isMuted = true
        notificationTokens.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.mediaSelectionDidChangeNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let item = note.object as? AVPlayerItem else { return }
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    self.refreshNativeTrackSelection(item)
                }
            })
        externalObservation = player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                let active = self.player.currentItem != nil && self.player.isExternalPlaybackActive
                self.externalPlaybackLossTask?.cancel(); self.externalPlaybackLossTask = nil
                if !active, self.externalPlaybackActive, self.usesSystemCarPlayVideo, let item = self.player.currentItem {
                    // Item/route negotiation can briefly report false. Keep the
                    // same surface through that transition. A stable system
                    // return to iPhone is authoritative and must not be forced back.
                    self.externalPlaybackLossTask = Task { [weak self, weak item] in
                        do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                        guard let self, let item, self.player.currentItem === item,
                              !self.player.isExternalPlaybackActive else { return }
                        self.externalPlaybackActive = false
                        if self.state == .playing || self.state == .paused { self.setPlaysOnPhone(true) }
                    }
                    return
                }
                if active {
                    self.continuingRemoteVideo = false
                    self.startupTask?.cancel(); self.startupTask = nil; self.waitingForExternalPlayback = false
                }
                if self.externalPlaybackActive != active {
                    self.externalPlaybackActive = active
                    if active {
                        AppMeasurement.shared.record(MeasurementEvent(name: .connection, outcome: .success, route: .airplay))
                    }
                    var values = DiagnosticValues()
                    values.externalPlayback = active
                    self.onDiagnostic?(.externalPlaybackChanged, values)
                }
            }
        }
        playingObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.compatibility == nil, self.casting == nil else { return }
                // Mounting a new output or a delayed player callback must not
                // undo Pause. Only an explicit Play (including AVKit PiP) may.
                if self.pauseRequested,
                   (self.pendingSeek != nil || (self.externalDisplayConnected && !self.playsOnPhone)),
                   !self.pictureInPictureActiveOrStarting,
                   self.player.timeControlStatus == .playing {
                    self.pause()
                    return
                }
                if self.shouldBlockCapturedPlayback,
                   self.player.timeControlStatus != .paused {
                    self.pause()
                    return
                }
                self.isPlaying = self.player.currentItem != nil && self.player.timeControlStatus == .playing
                if self.player.currentItem != nil {
                    switch self.player.timeControlStatus {
                    case .playing:
                        self.state = .playing
                        // AVKit's PiP controls can resume AVPlayer directly.
                        self.pauseRequested = false
                    case .waitingToPlayAtSpecifiedRate: self.state = .loading
                    default: if self.state != .loading { self.state = .paused }
                    }
                }
                if self.isPlaying && !self.waitingForExternalPlayback { self.startupTask?.cancel(); self.startupTask = nil }
                if self.activatedAudioSession {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
                }
                if self.player.timeControlStatus == .paused, self.state == .paused {
                    self.carPlayBridge?.setPaused(true)
                }
                if self.player.timeControlStatus == .playing {
                    if self.continuingRemoteVideo, !self.player.isExternalPlaybackActive, let item = self.player.currentItem {
                        self.externalPlaybackLossTask?.cancel()
                        self.externalPlaybackLossTask = Task { [weak self, weak item] in
                            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                            guard let self, let item, self.player.currentItem === item,
                                  !self.player.isExternalPlaybackActive else { return }
                            self.continuingRemoteVideo = false
                            self.externalPlaybackActive = false
                        }
                    }
                    self.carPlayBridge?.setPaused(false)
                    self.stallTask?.cancel()
                    self.stallTask = nil
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
                        guard self.hasActivePlayback else { return }
                        if self.interruptedPlaybackID != self.playbackID {
                            // Buffering and restoring a saved position still
                            // carry a Play request, even before the first frame.
                            self.resumeAfterInterruption = !self.pauseRequested && (self.isPlaying || self.state == .loading)
                            self.interruptedPlaybackID = self.playbackID
                        }
                        if let compatibility = self.compatibility { compatibility.pause() } else { self.player.pause() }
                        self.carPlayBridge?.setPaused(true)
                        self.isPlaying = false
                    } else {
                        let flags = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                        let interruptedID = self.interruptedPlaybackID
                        let shouldResume = self.resumeAfterInterruption && !self.pauseRequested
                        self.interruptedPlaybackID = nil
                        self.resumeAfterInterruption = false
                        guard self.playbackID == interruptedID else { return }
                        guard flags & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0, shouldResume else {
                            self.pause()
                            return
                        }
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.resume()
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
                        // Live sources can briefly buffer during a channel
                        // handoff. Give the current item time to recover before
                        // turning a stall into a playback failure.
                        try? await Task.sleep(for: .seconds(30))
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
        liveSourcePreparation?.cancel()
        externalPlaybackLossTask?.cancel()
        let bridge = carPlayBridge
        Task { @MainActor in bridge?.stop() }
        mediaRelay?.stop()
        personalMediaServer?.stop()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func play(url: URL, preserveSourceAudio: Bool = true, muted: Bool = false,
              requiresExternalPlayback: Bool = true, title: String? = nil, live: Bool = true,
              presentation: MediaPlaybackPresentation = .video, useCompatibility: Bool = false,
              startAt: Double = 0, startPaused: Bool = false, recoveryAttempt: Int = 0, lowLatency: Bool = false,
              artworkURL: URL? = nil) throws {
        do {
            try preparePlayback(url: url, preserveSourceAudio: preserveSourceAudio, muted: muted,
                requiresExternalPlayback: requiresExternalPlayback, title: title, live: live,
                presentation: presentation, useCompatibility: useCompatibility, startAt: startAt,
                startPaused: startPaused, recoveryAttempt: recoveryAttempt, lowLatency: lowLatency, artworkURL: artworkURL)
        } catch {
            measurement.finish(failed: true)
            AppMeasurement.shared.failure(.playbackError, error: error)
            throw error
        }
    }

    private func preparePlayback(url: URL, preserveSourceAudio: Bool = true, muted: Bool = false,
              requiresExternalPlayback: Bool = true, title: String? = nil, live: Bool = true,
              presentation: MediaPlaybackPresentation = .video, useCompatibility: Bool = false,
              startAt: Double = 0, startPaused: Bool = false, recoveryAttempt: Int = 0, lowLatency: Bool = false,
              artworkURL: URL? = nil) throws {
        // A Cast load replaces the receiver's current media by itself. Sending
        // STOP first adds an avoidable round trip and makes channel changes
        // visibly stall on the TV.
        let replacingCastMedia = tvDevice != nil && casting != nil && !url.isFileURL
        let resumePiPAfterReplacement = presentation == .video && !stoppingPiP && !restorePiPOnStart &&
            (pictureInPictureActiveOrStarting || pendingAutomaticPiP) && tvDevice == nil &&
            !hasRemoteVideoOutput
        let wasBackgrounded = enteredBackgroundWithVideo
        let preserveVideoRoute = presentation == .video && tvDevice == nil && !playsOnPhone && hasActivePlayback
        stop(stopRemoteCastMedia: !replacingCastMedia, deactivateAudioSession: tvDevice != nil,
             preserveVideoRoute: preserveVideoRoute)
        videoReadyForDisplay = presentation != .video
        measurement.begin(route: tvDevice != nil ? .cast : externalDisplayConnected ? .external
            : requiresExternalPlayback && !playsOnPhone ? .airplay : .phone)
        enteredBackgroundWithVideo = wasBackgrounded && presentation == .video && tvDevice == nil
        pendingAutomaticPiP = resumePiPAfterReplacement
        liveRecoveryAttempt = recoveryAttempt
        let attemptID = playbackID
        if carPlayConnected { CarPlayPlaybackTrace.record("selection") }
        request = Request(url: url, preserveSourceAudio: preserveSourceAudio, muted: muted,
                          requiresExternalPlayback: requiresExternalPlayback, title: title, live: live,
                          presentation: presentation, useCompatibility: useCompatibility, lowLatency: lowLatency,
                          artworkURL: artworkURL)
        preparingCarPlayVideo = usesSystemCarPlayVideo
        let position = startAt.isFinite ? max(0, startAt) : 0
        currentTime = position
        let startsPaused = startPaused || (screenCaptureBlocked && !hasRemoteVideoOutput && presentation == .video)
        pauseRequested = startsPaused
        requestedLive = live
        isLive = live
        errorMessage = nil
        // Video capability is not a request to move playback. The system may
        // keep audio playing or let the user decline the CarPlay video prompt.
        waitingForExternalPlayback = requiresExternalPlayback && presentation == .video && tvDevice == nil && !usesOwnedVideoDisplay && !playsOnPhone
        player.isMuted = muted
        updateVideoOutput()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title ?? L10n.tr("iPhone ekranı"),
            MPMediaItemPropertyArtist: BrandIdentity.name,
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyMediaType: presentation == .audio ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0
        ]
        updateNowPlayingArtwork(url: artworkURL)
        if let device = tvDevice {
            let cast = CastPlayback()
            casting = cast
            state = .loading
            cast.onState = { [weak self, weak cast] state in
                guard let self, let cast, self.casting === cast else { return }
                if state == .failed {
                    self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .playback, expectedPlaybackID: attemptID)
                    return
                }
                self.state = state
                self.isPlaying = state == .playing
                if state == .playing || state == .paused {
                    self.pauseRequested = state == .paused
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
                        cast.open(url: address, device: device, title: title, live: false, startAt: position, paused: startsPaused)
                    }
                }, onFailure: { [weak self, weak cast] in
                    Task { @MainActor in
                        guard let self, let cast, self.casting === cast else { return }
                        self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .unavailable, expectedPlaybackID: attemptID)
                    }
                })
            } else {
                cast.open(url: url, device: device, title: title, live: live, startAt: position, paused: startsPaused)
            }
            guard casting === cast else { return }
            installRemoteCommands()
            startupTask = Task { [weak self, weak cast] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, let cast, self.casting === cast, self.state == .loading else { return }
                self.fail(L10n.tr("TV bağlantısı kurulamadı. TV’yi ve Wi-Fi bağlantısını kontrol edip yeniden dene."), reason: .unavailable, expectedPlaybackID: attemptID)
            }
            return
        }
        // The Cast receiver handles playback audio. Avoid synchronously
        // reconfiguring the phone's audio session during remote channel swaps.
        // Mixing avoids deliberately taking over the source application's audio.
        let session = AVAudioSession.sharedInstance()
        if presentation == .audio {
            if session.category != .playback || session.mode != .default ||
                session.routeSharingPolicy != .longFormAudio || !session.categoryOptions.isEmpty {
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            }
        } else if preserveSourceAudio {
            if session.category != .playback || session.mode != .moviePlayback || session.categoryOptions != [.mixWithOthers] {
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            }
        } else {
            if session.category != .playback || session.mode != .moviePlayback ||
                session.routeSharingPolicy != .longFormVideo || !session.categoryOptions.isEmpty {
                try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
            }
        }
        try session.setActive(true)
        activatedAudioSession = true
        if useCompatibility && !usesSystemCarPlayVideo {
            recordPlaybackSource(url: url, engine: .compatibility, transport: .direct)
            let engine = CompatibilityPlayback()
            engine.setBroadcastCaptureActive(broadcastCaptureActive)
            compatibility = engine
            engine.setExternalVideoEnabled(!playsOnPhone)
            engine.onTracksChanged = { [weak self, weak engine] in
                guard let self, let engine, self.compatibility === engine else { return }
                self.audioTracks = engine.audioChoices
                self.subtitleTracks = engine.subtitleChoices
                self.canDisableSubtitles = !self.subtitleTracks.isEmpty
            }
            engine.onPiPReady = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.pictureInPictureAvailabilityChanged()
            }
            engine.onPiPStarted = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.pictureInPictureStarted()
            }
            engine.onPiPStopped = { [weak self, weak engine] in
                guard let self, let engine else { return }
                if self.compatibility === engine { self.pictureInPictureStopped() }
                self.pictureInPictureSourceStopped(engine)
            }
            engine.onPiPWillStop = { [weak self, weak engine] in
                guard let self, self.compatibility === engine else { return }
                self.pictureInPictureWillStop()
            }
            engine.onVideoReady = { [weak self, weak engine] in
                guard let self, let engine, self.compatibility === engine,
                      self.request?.presentation == .video else { return }
                self.videoReadyForDisplay = true
            }
            state = .loading
            var resumePosition: Double? = position > 0 ? position : nil
            var startingPlayback = true
            engine.onState = { [weak self, weak engine] state in
                guard let self, let engine, self.compatibility === engine else { return }
                if state == .playing, self.shouldBlockCapturedPlayback {
                    self.pause()
                    return
                }
                if state == .failed {
                    self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .playback, expectedPlaybackID: attemptID)
                    return
                }
                if state == .playing, self.interruptedPlaybackID == self.playbackID {
                    engine.pause()
                    self.isPlaying = false
                    return
                }
                if state == .playing { self.startPendingPictureInPicture() }
                let initialPlayback = startingPlayback && state == .playing
                if state == .playing { startingPlayback = false }
                if state == .playing, let position = resumePosition {
                    resumePosition = nil
                    self.restoreCompatibilityPosition(position, engine: engine)
                    return
                }
                if self.restoringCompatibilityPosition { return }
                if state == .playing, self.pauseRequested,
                   initialPlayback || (self.externalDisplayConnected && !self.playsOnPhone && !self.pictureInPictureActiveOrStarting) {
                    self.pause()
                    return
                }
                // After startup, a direct PiP Play request is authoritative.
                if state == .playing {
                    self.pauseRequested = false
                    if lowLatency { self.liveRecoveryAttempt = 0 }
                }
                self.state = state
                self.isPlaying = state == .playing
                if self.isPlaying { self.startupTask?.cancel(); self.startupTask = nil }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
            }
            engine.onTime = { [weak self, weak engine] time, length in
                guard let self, let engine, self.compatibility === engine, self.pendingSeek == nil, resumePosition == nil else { return }
                self.updateTimeline(time: time, length: lowLatency ? 0 : length,
                                    seekable: !lowLatency && engine.isMediaSeekable(), live: self.requestedLive)
            }
            engine.onFinished = { [weak self, weak engine] in
                guard let self, let engine, self.compatibility === engine else { return }
                if lowLatency {
                    self.fail(L10n.tr("Yayın bağlantısı kesildi. Yeniden deneyebilirsin."), reason: .interrupted, expectedPlaybackID: attemptID)
                    return
                }
                self.stop(); self.onFinished?()
            }
            engine.onRestore = { [weak self, weak engine] completion in
                guard let self, self.compatibility === engine else { completion(false); return }
                self.restoreUserInterfaceForPictureInPictureStop(completion: completion)
            }
            engine.open(url, lowLatency: lowLatency)
            if lowLatency { engine.mediaPlayer.audio?.isMuted = muted }
            installRemoteCommands(); recordAudioRoute()
            startupTask = Task { [weak self, weak engine] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, let engine, self.compatibility === engine, !self.isPlaying else { return }
                self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .unavailable, expectedPlaybackID: attemptID)
            }
            return
        }
        installRemoteCommands()
        recordAudioRoute()
        if usesSystemCarPlayVideo, MediaChannel(title: "", url: url).requiresCompatibilityPlayback {
            if requestedLive && CarPlayMediaSource.hlsCandidate(for: url) != nil {
                prepareLiveCarPlaySource(url: url, attemptID: attemptID)
            } else { startCarPlayBridge(url: url, position: position, attemptID: attemptID) }
        } else if usesSystemCarPlayVideo,
           url.isFileURL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            try startLocalExternalPlayback(file: url, position: position, attemptID: attemptID)
        } else if usesSystemCarPlayVideo, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            // The receiver must not first fail on provider credentials, then
            // reopen the same stream and display a second system route banner.
            try startRelayedPlayback(url: url, position: position, attemptID: attemptID)
        } else {
            startNativePlayback(url: url, position: position, startsPaused: startsPaused, attemptID: attemptID)
        }
    }

    private func prepareLiveCarPlaySource(url: URL, attemptID: UUID) {
        state = .loading
        liveSourcePreparation = Task { [weak self] in
            let alternative = try? await CarPlayMediaResolver.nativeAlternative(for: url)
            guard let self, !Task.isCancelled, self.playbackID == attemptID else { return }
            self.liveSourcePreparation = nil
            if let alternative {
                do {
                    try self.startRelayedPlayback(url: alternative, position: 0, attemptID: attemptID)
                    return
                } catch { /* The original source still has a local conversion path. */ }
            }
            self.startCarPlayBridge(url: url, position: 0, attemptID: attemptID)
        }
    }

    private func startCarPlayBridge(url: URL, position: Double, attemptID: UUID, forceTranscode: Bool = false) {
        clearNativeItemForReplacement()
        carPlayBridge?.stop()
        mediaRelay?.stop(); mediaRelay = nil
        personalMediaServer?.stop(); personalMediaServer = nil
        bridgeTimeOrigin = nil
        let bridge = CarPlayHLSBridge(source: url, live: requestedLive, startPosition: position, forceTranscode: forceTranscode)
        carPlayBridge = bridge
        state = .loading
        currentTime = position
        bridge.onReady = { [weak self, weak bridge] address in
            guard let self, let bridge, self.carPlayBridge === bridge, self.playbackID == attemptID else { return }
            self.duration = bridge.duration
            self.canSeek = bridge.duration > 0 && !self.requestedLive
            self.startNativePlayback(url: address, position: bridge.supportsNativeSeeking ? bridge.startPosition : 0,
                                     startsPaused: self.pauseRequested, attemptID: attemptID)
        }
        bridge.onFailure = { [weak self, weak bridge] error in
            guard let self, let bridge, self.carPlayBridge === bridge, self.playbackID == attemptID else { return }
            if bridge.canRetryTranscoding {
                self.startCarPlayBridge(url: url, position: self.requestedLive ? 0 : self.currentTime,
                                        attemptID: attemptID, forceTranscode: true)
            } else {
                self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .preparation,
                          failure: DiagnosticFailure(error), expectedPlaybackID: attemptID)
            }
        }
        bridge.start()
    }

    private func clearNativeItemForReplacement() {
        player.cancelPendingPrerolls()
        carPlayPrerollItem = nil
        carPlayPrerollPending = false
        carPlayPrerollReady = false
        preparingCarPlayVideo = usesSystemCarPlayVideo
        updateVideoOutput()
        continuingRemoteVideo = usesSystemCarPlayVideo && hasRemoteVideoOutput
        externalPlaybackLossTask?.cancel(); externalPlaybackLossTask = nil
        itemObservation = nil; durationObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        trackLoadingTask?.cancel(); trackLoadingTask = nil
        qualityLoadingTask?.cancel(); qualityLoadingTask = nil
        startupTask?.cancel(); startupTask = nil
        pendingSeek = nil; nativeResumePosition = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        videoReadyForDisplay = false
        isPlaying = false
    }

    private func startRelayedPlayback(url: URL, position: Double, attemptID: UUID) throws {
        let relay = try MediaRelayServer(source: url)
        mediaRelay = relay
        clearNativeItemForReplacement()
        isPlaying = false; state = .loading
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.playbackID == attemptID, self.player.currentItem == nil else { return }
            self.fail(self.displayConnection.failureMessage, reason: .unavailable, expectedPlaybackID: attemptID)
        }
        relay.start(onReady: { [weak self, weak relay] address in
            Task { @MainActor in
                guard let self, let relay, self.mediaRelay === relay, self.playbackID == attemptID else { return }
                self.startNativePlayback(url: address, position: position, startsPaused: self.pauseRequested, attemptID: attemptID)
            }
        }, onFailure: { [weak self, weak relay] error in
            Task { @MainActor in
                guard let self, let relay, self.mediaRelay === relay, self.playbackID == attemptID else { return }
                self.fail(self.displayConnection.failureMessage, reason: .preparation,
                          failure: DiagnosticFailure(error), expectedPlaybackID: attemptID)
            }
        })
    }

    /// CarPlay's system video receiver can reject a device-local file URL with
    /// AVError.externalPlaybackNotSupportedForAsset. Serve the same bytes using
    /// the bounded, range-capable server already used for selected Cast files.
    /// Keep request.url local so retries, history and route changes retain the source.
    private func startLocalExternalPlayback(file: URL, position: Double, attemptID: UUID) throws {
        let server = try PersonalMediaServer(file: file)
        personalMediaServer = server
        itemObservation = nil
        durationObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        trackLoadingTask?.cancel(); trackLoadingTask = nil
        qualityLoadingTask?.cancel(); qualityLoadingTask = nil
        pendingSeek = nil
        nativeResumePosition = position
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        state = .loading
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.playbackID == attemptID, self.player.currentItem == nil else { return }
            self.fail(self.displayConnection.failureMessage, reason: .unavailable, expectedPlaybackID: attemptID)
        }
        server.start(onReady: { [weak self, weak server] address in
            Task { @MainActor in
                guard let self, let server, self.playbackID == attemptID,
                      self.personalMediaServer === server else { return }
                self.startNativePlayback(url: address, position: position,
                    startsPaused: self.pauseRequested, attemptID: attemptID)
            }
        }, onFailure: { [weak self, weak server] in
            Task { @MainActor in
                guard let self, let server, self.playbackID == attemptID,
                      self.personalMediaServer === server else { return }
                self.fail(self.displayConnection.failureMessage, reason: .unavailable, expectedPlaybackID: attemptID)
            }
        })
    }

    private func startNativePlayback(url: URL, position: Double, startsPaused: Bool, attemptID: UUID) {
        recordPlaybackSource(url: request?.url ?? url, engine: .native,
                             transport: carPlayBridge != nil ? .converted : mediaRelay != nil ? .relay : personalMediaServer != nil ? .localFile : .direct)
        startupTask?.cancel(); startupTask = nil
        let item = AVPlayerItem(url: url)
        carPlayPrerollItem = usesSystemCarPlayVideo ? item : nil
        carPlayPrerollPending = false
        carPlayPrerollReady = false
        applySubtitlePosition(to: item)
        // Pausing at startup must not seek a live stream to time zero.
        nativeResumePosition = position > 0 || (carPlayBridge != nil && carPlayBridge?.supportsNativeSeeking != true && !requestedLive) ? position : nil
        item.preferredForwardBufferDuration = requestedLive ? 1 : 2
        player.automaticallyWaitsToMinimizeStalling = !(requestedLive && usesSystemCarPlayVideo)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.fail(L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."),
                              reason: .playback, failure: item.error.map(DiagnosticFailure.init), expectedPlaybackID: attemptID)
                } else if item.status == .readyToPlay {
                    if self.usesSystemCarPlayVideo { CarPlayPlaybackTrace.record("native-ready") }
                    if self.carPlayBridge != nil {
                        self.bridgeTimeOrigin = item.seekableTimeRanges.first?.timeRangeValue.start.seconds ?? 0
                    }
                    self.loadNativeTracks(item)
                    self.loadNativeVideoQualities(item)
                    self.startPendingPictureInPicture()
                    guard let position = self.nativeResumePosition, self.pendingSeek == nil else {
                        self.refreshNativeTimeline(item)
                        if self.pauseRequested { self.pause() }
                        if self.usesSystemCarPlayVideo { self.prepareCarPlayPreroll(item) }
                        return
                    }
                    let seekID = UUID()
                    self.pendingSeek = seekID
                    let nativePosition = self.carPlayBridge != nil && self.carPlayBridge?.supportsNativeSeeking != true
                        ? self.bridgeTimeOrigin ?? 0 : position
                    self.player.seek(to: CMTime(seconds: nativePosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] _ in
                        Task { @MainActor in
                            guard let self, let item, self.player.currentItem === item, self.pendingSeek == seekID else { return }
                            self.pendingSeek = nil
                            self.nativeResumePosition = nil
                            self.refreshNativeTimeline(item)
                            if self.pauseRequested { self.pause() }
                            else { self.resume() }
                            if self.usesSystemCarPlayVideo { self.prepareCarPlayPreroll(item) }
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
        if nativeResumePosition == nil && !startsPaused { playNative() }
        startupTask = Task { [weak self, weak item] in
            // Some IPTV endpoints need longer than a few seconds to return
            // the first playable segment after a channel switch.
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let item, self.player.currentItem === item,
                  (self.waitingForExternalPlayback ? !self.player.isExternalPlaybackActive : self.player.timeControlStatus != .playing) else { return }
            self.fail(self.waitingForExternalPlayback ? self.displayConnection.failureMessage : L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene."), reason: .unavailable, expectedPlaybackID: attemptID)
        }
    }

    func prepareCarPlayResume(_ saved: LastPlaybackRecord, presentation: MediaPlaybackPresentation,
                              onPlay: @escaping () -> Void) throws {
        guard !hasActivePlayback else { return }
        stop()
        // Claim Now Playing without creating a decoder or opening the media URL.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try session.setActive(true)
        activatedAudioSession = true
        pendingCarPlayResume = onPlay
        currentTime = saved.resumePosition
        duration = saved.duration
        isLive = saved.isLive
        var metadata: [String: Any] = [
            MPMediaItemPropertyTitle: saved.title,
            MPMediaItemPropertyArtist: BrandIdentity.name,
            MPNowPlayingInfoPropertyIsLiveStream: saved.isLive,
            MPNowPlayingInfoPropertyMediaType: presentation == .audio ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: saved.resumePosition,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0
        ]
        if saved.duration > 0 { metadata[MPMediaItemPropertyPlaybackDuration] = saved.duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
        updateNowPlayingArtwork(url: saved.channel.metadata.artworkURL)
        installRemoteCommands()
    }

    private func updateNowPlayingArtwork(url: URL?) {
        nowPlayingArtworkTask?.cancel()
        let attemptID = playbackID
        func publish(_ image: UIImage) {
            guard var metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            metadata[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
        }
        // Give CarPlay artwork immediately, then replace it without blocking
        // playback. iOS owns the cover layout and the blurred background.
        if let cached = url.flatMap({ MediaArtworkStore.shared.cachedImage(at: $0) }) {
            publish(cached)
            return
        }
        if let fallback = UIImage(named: "MirivoMark") { publish(fallback) }
        guard let url else { return }
        nowPlayingArtworkTask = Task { [weak self] in
            guard let image = await MediaArtworkStore.shared.image(at: url), !Task.isCancelled,
                  let self, self.playbackID == attemptID else { return }
            publish(image)
        }
    }

    func stop(stopRemoteCastMedia: Bool = true, deactivateAudioSession: Bool = true, preserveVideoRoute: Bool = false) {
        preparingCarPlayVideo = false
        carPlayPrerollItem = nil
        carPlayPrerollPending = false
        carPlayPrerollReady = false
        player.cancelPendingPrerolls()
        pendingCarPlayResume = nil
        nowPlayingArtworkTask?.cancel(); nowPlayingArtworkTask = nil
        continuingRemoteVideo = preserveVideoRoute && (externalPlaybackActive || continuingRemoteVideo)
        measurement.finish()
        playbackID = UUID()
        videoReadyForDisplay = false
        liveRecoveryTask?.cancel(); liveRecoveryTask = nil
        liveRecoveryAttempt = 0
        foregroundPiPRestoreTask?.cancel(); foregroundPiPRestoreTask = nil
        liveSourcePreparation?.cancel(); liveSourcePreparation = nil
        externalPlaybackLossTask?.cancel(); externalPlaybackLossTask = nil
        carPlayBridge?.stop(); carPlayBridge = nil
        bridgeTimeOrigin = nil
        mediaRelay?.stop(); mediaRelay = nil
        let previousNativePiP = currentNativePiP
        let previousNativeController = (retainedPiPController as? NativeVideoController) ??
            (previousNativePiP?.delegate as? NativeVideoController)
        let previousCompatibility = compatibility
        if let previousNativeController,
           previousNativeController.startingPiP || previousNativePiP?.isPictureInPictureActive == true {
            retiringPiPSources.insert(ObjectIdentifier(previousNativeController))
        }
        if let previousCompatibility,
           previousCompatibility.pipActive || previousCompatibility.pipStarting || startingPiP {
            retiringPiPSources.insert(ObjectIdentifier(previousCompatibility))
        }
        retainedPiPController = nil
        nativePiP = nil
        trackLoadingTask?.cancel(); trackLoadingTask = nil
        qualityLoadingTask?.cancel(); qualityLoadingTask = nil
        videoQualities = []; selectedVideoQualityID = nil
        audioGroup = nil; subtitleGroup = nil
        nativeAudioOptions = []; nativeSubtitleOptions = []
        audioTracks = []; subtitleTracks = []; canDisableSubtitles = false
        pendingAutomaticPiP = false
        startingPiP = false
        stoppingPiP = false
        enteredBackgroundWithVideo = false
        restorePiPOnStart = false
        foregroundPiPRestoreID = nil
        if let previousNativeController { previousNativeController.stopForPlaybackReplacement() }
        else { previousNativePiP?.stopPictureInPicture() }
        personalMediaServer?.stop(); personalMediaServer = nil
        MediaScreenAwake.release(localCastAwakeLease); localCastAwakeLease = nil
        request = nil
        nativeResumePosition = nil
        restoringCompatibilityPosition = false
        pauseRequested = false
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        durationObservation = nil
        pendingSeek = nil
        casting?.stop(stopRemoteMedia: stopRemoteCastMedia); casting = nil
        compatibility = nil
        previousCompatibility?.stop()
        currentTime = 0; duration = 0
        canSeek = false; isLive = false; requestedLive = false
        startupTask?.cancel()
        startupTask = nil
        waitingForExternalPlayback = false
        stallTask?.cancel(); stallTask = nil
        interruptedPlaybackID = nil
        resumeAfterInterruption = false
        remoteTargets.forEach { $0.0.removeTarget($0.1); $0.0.isEnabled = false }; remoteTargets.removeAll()
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if activatedAudioSession { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        isPlaying = false
        state = .idle
        errorMessage = nil
        if !preserveVideoRoute {
            externalPlaybackActive = false
            player.allowsExternalPlayback = false
            player.usesExternalPlaybackWhileExternalScreenIsActive = false
        }
        if activatedAudioSession && deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            activatedAudioSession = false
        }
    }

    private func restoreCompatibilityPosition(_ position: Double, engine: CompatibilityPlayback) {
        // VLC's start-time input option may jump to a later keyframe. Restore
        // with the same accurate seek path used by the timeline, after opening.
        restoringCompatibilityPosition = true
        let seekID = UUID()
        pendingSeek = seekID
        currentTime = position
        // Keep an autoplaying decoder running while it seeks. Pausing it here
        // can leave startup waiting for a frame that the decoder cannot produce.
        if pauseRequested { engine.pause() }
        engine.seek(to: position) { [weak self, weak engine] in
            guard let self, let engine, self.compatibility === engine, self.pendingSeek == seekID else { return }
            self.pendingSeek = nil
            self.restoringCompatibilityPosition = false
            self.updateTimeline(time: Double(engine.mediaTime()) / 1000, length: Double(engine.mediaLength()) / 1000,
                                seekable: engine.isMediaSeekable(), live: self.requestedLive)
            if self.pauseRequested { self.pause() }
            else {
                self.resume()
                // An autoplaying seek need not change VLC's playing state,
                // so there may be no new state callback after it completes.
                if self.interruptedPlaybackID == nil, engine.isMediaPlaying() {
                    self.state = .playing
                    self.isPlaying = true
                    self.startupTask?.cancel(); self.startupTask = nil
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                }
            }
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
        let paused = state == .paused || pauseRequested
        tvDevice = device
        if device != nil { playsOnPhone = false }
        if device == nil { casting?.stop(); CastPlayback.disconnect() }
        if previous?.lowLatency == true { stop(); return }
        guard let previous, hasActivePlayback || state == .failed else { return }
        try play(url: previous.url, preserveSourceAudio: previous.preserveSourceAudio, muted: previous.muted,
                 requiresExternalPlayback: device == nil && previous.requiresExternalPlayback,
                 title: previous.title, live: live, presentation: previous.presentation,
                 useCompatibility: previous.useCompatibility, startAt: position, startPaused: paused,
                 lowLatency: previous.lowLatency, artworkURL: previous.artworkURL)
    }

    func togglePlayPause() {
        guard hasActivePlayback || pendingCarPlayResume != nil else { return }
        if isPlaying || (state == .loading && !pauseRequested) { pause() } else { resume() }
    }

    func selectAudioTrack(_ id: String) {
        if let compatibility { compatibility.selectAudioTrack(id); return }
        guard let item = player.currentItem, let group = audioGroup,
              let index = audioTracks.firstIndex(where: { $0.id == id }), nativeAudioOptions.indices.contains(index) else { return }
        item.select(nativeAudioOptions[index], in: group)
        refreshNativeTrackSelection(item)
    }

    func selectSubtitleTrack(_ id: String?) {
        if let compatibility { compatibility.selectSubtitleTrack(id); return }
        guard let item = player.currentItem, let group = subtitleGroup else { return }
        if let id {
            guard let index = subtitleTracks.firstIndex(where: { $0.id == id }), nativeSubtitleOptions.indices.contains(index) else { return }
            item.select(nativeSubtitleOptions[index], in: group)
        } else {
            guard group.allowsEmptySelection else { return }
            item.select(nil, in: group)
        }
        refreshNativeTrackSelection(item)
    }

    func selectVideoQuality(_ id: String?) {
        guard showsVideoQuality, compatibility == nil, let item = player.currentItem else { return }
        let quality = videoQualities.first { $0.id == id }
        guard id == nil || quality != nil else { return }
        // Keep the master playlist, current item, audio/subtitle selection and
        // timeline. AVPlayer may adapt below this ceiling as bandwidth changes.
        item.preferredMaximumResolution = quality?.resolution ?? .zero
        selectedVideoQualityID = id
    }

    private func loadNativeVideoQualities(_ item: AVPlayerItem) {
        guard request?.presentation == .video, let asset = item.asset as? AVURLAsset else { return }
        qualityLoadingTask?.cancel()
        qualityLoadingTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let variants = (try? await asset.load(.variants)) ?? []
            guard !Task.isCancelled, self.player.currentItem === item, self.compatibility == nil else { return }
            // Only advertise sizes actually declared by the HLS master. A
            // single MP4/MKV file cannot acquire other encodes through scaling.
            var qualities: [String: PlaybackVideoQuality] = [:]
            for variant in variants {
                guard let size = variant.videoAttributes?.presentationSize,
                      let width = Int(exactly: size.width), let height = Int(exactly: size.height),
                      width > 0, height > 0 else { continue }
                let quality = PlaybackVideoQuality(resolution: size)
                qualities[quality.id] = quality
            }
            let options = qualities.values.sorted {
                let lhs = $0.resolution.width * $0.resolution.height
                let rhs = $1.resolution.width * $1.resolution.height
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }
            self.videoQualities = options.count > 1 ? options : []
        }
    }

    private func loadNativeTracks(_ item: AVPlayerItem) {
        trackLoadingTask?.cancel()
        trackLoadingTask = Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            let audio = try? await item.asset.loadMediaSelectionGroup(for: .audible)
            let subtitles = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            guard !Task.isCancelled, self.player.currentItem === item, self.compatibility == nil else { return }
            self.audioGroup = audio; self.subtitleGroup = subtitles
            self.nativeAudioOptions = audio?.options ?? []
            // AVFoundation can synthesize forced-only variants of the same
            // subtitle track. Keep ordinary language choices in the picker.
            self.nativeSubtitleOptions = subtitles?.options.filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) } ?? []
            self.refreshNativeTrackSelection(item)
        }
    }

    private func refreshNativeTrackSelection(_ item: AVPlayerItem) {
        func choices(_ group: AVMediaSelectionGroup?, options: [AVMediaSelectionOption], prefix: String) -> [PlaybackTrack] {
            guard let group else { return [] }
            let selected = item.currentMediaSelection.selectedMediaOption(in: group)
            return options.enumerated().map { index, option in
                PlaybackTrack(id: "\(prefix)-\(index)", title: option.displayName, isSelected: option == selected)
            }
        }
        audioTracks = choices(audioGroup, options: nativeAudioOptions, prefix: "audio")
        subtitleTracks = choices(subtitleGroup, options: nativeSubtitleOptions, prefix: "subtitle")
        canDisableSubtitles = subtitleGroup?.allowsEmptySelection == true
    }

    func resume() {
        guard !shouldBlockCapturedPlayback else { return }
        if let pendingCarPlayResume { pendingCarPlayResume(); return }
        pauseRequested = false
        if interruptedPlaybackID == playbackID {
            resumeAfterInterruption = true
            return
        }
        // AVPlayer must finish its initial seek before receiving Play. The
        // completion reads the latest request, including an explicit resume.
        guard nativeResumePosition == nil else { return }
        if hasActivePlayback && !isPlaying { state = .loading }
        carPlayBridge?.setPaused(false)
        if let casting { casting.play() }
        else if let compatibility { compatibility.play() } else if player.currentItem != nil { playNative() }
    }

    private func playNative() {
        if usesSystemCarPlayVideo, let item = player.currentItem, carPlayPrerollItem === item {
            guard carPlayPrerollReady else {
                prepareCarPlayPreroll(item)
                return
            }
            CarPlayPlaybackTrace.record("play-ready")
        }
        if requestedLive && usesSystemCarPlayVideo { player.playImmediately(atRate: 1) }
        else { player.play() }
    }

    private func prepareCarPlayPreroll(_ item: AVPlayerItem) {
        guard usesSystemCarPlayVideo, player.currentItem === item, carPlayPrerollItem === item,
              item.status == .readyToPlay, player.status == .readyToPlay,
              nativeResumePosition == nil, pendingSeek == nil,
              !carPlayPrerollPending, !carPlayPrerollReady else { return }
        carPlayPrerollPending = true
        CarPlayPlaybackTrace.record("preroll-start")
        player.preroll(atRate: 1) { [weak self, weak item] finished in
            Task { @MainActor in
                guard let self, let item, self.player.currentItem === item,
                      self.carPlayPrerollItem === item else { return }
                self.carPlayPrerollPending = false
                guard finished else { return }
                self.carPlayPrerollReady = true
                self.preparingCarPlayVideo = false
                self.updateVideoOutput()
                CarPlayPlaybackTrace.record("preroll-ready")
                if !self.pauseRequested { self.playNative() }
            }
        }
    }

    func seek(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        guard hasActivePlayback, canSeek, seconds.isFinite else { return }
        let target = min(max(0, seconds), duration)
        if let bridge = carPlayBridge, !bridge.supportsNativeSeeking, let source = self.request {
            // This HLS window is bounded; seeking a movie is a source seek,
            // not a seek into a short rolling live window on the receiver.
            startCarPlayBridge(url: source.url, position: target, attemptID: playbackID,
                               forceTranscode: bridge.transcodesVideo)
            return
        }
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
                    if self.pauseRequested { self.pause() }
                    self.refreshNativeTimeline(item)
                }
            }
        }
    }

    private func refreshNativeTimeline(_ item: AVPlayerItem) {
        guard player.currentItem === item, compatibility == nil, casting == nil, pendingSeek == nil, nativeResumePosition == nil else { return }
        if let bridge = carPlayBridge {
            let time = player.currentTime().seconds
            let origin = bridgeTimeOrigin ?? 0
            updateTimeline(time: bridge.supportsNativeSeeking ? time : bridge.startPosition + max(0, time - origin), length: bridge.duration,
                           seekable: bridge.duration > 0 && item.status == .readyToPlay, live: requestedLive)
            return
        }
        let seekable = item.status == .readyToPlay && item.seekableTimeRanges.contains {
            let length = $0.timeRangeValue.duration.seconds
            return length.isFinite && length > 0
        }
        updateTimeline(time: player.currentTime().seconds, length: item.duration.seconds,
                       seekable: seekable, live: item.duration.isIndefinite || requestedLive)
    }

    private func updateTimeline(time: Double, length: Double, seekable: Bool, live: Bool) {
        let nextDuration = length.isFinite && length > 0 ? length : 0
        let nextTime = time.isFinite ? max(0, nextDuration > 0 ? min(time, nextDuration) : time) : 0
        let nextLive = nextDuration > 0 ? false : live
        let nextSeekable = nextDuration > 0 && seekable
        guard duration != nextDuration || currentTime != nextTime || isLive != nextLive || canSeek != nextSeekable else { return }
        if duration != nextDuration { duration = nextDuration }
        if currentTime != nextTime { currentTime = nextTime }
        // A finite duration also identifies VOD served as an HLS or extensionless URL.
        if isLive != nextLive { isLive = nextLive }
        if canSeek != nextSeekable { canSeek = nextSeekable }
        guard var metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        metadata[MPNowPlayingInfoPropertyIsLiveStream] = isLive
        if duration > 0 { metadata[MPMediaItemPropertyPlaybackDuration] = duration }
        else { metadata.removeValue(forKey: MPMediaItemPropertyPlaybackDuration) }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
    }

    func pause() {
        pauseRequested = true
        resumeAfterInterruption = false
        startupTask?.cancel(); startupTask = nil
        carPlayBridge?.setPaused(true)
        if let casting { casting.pause() }
        else if let compatibility { compatibility.pause() } else { player.pause() }
        isPlaying = false
        state = .paused
    }

    func updateRemoteTrackCommands() {
        let available = (hasActivePlayback || pendingCarPlayResume != nil) ? remoteTrackAvailability?() : nil
        let center = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.isEnabled = onRemoteTrackChange != nil && available?.previous == true
        center.nextTrackCommand.isEnabled = onRemoteTrackChange != nil && available?.next == true
    }

    func changeTrack(_ offset: Int) {
        guard hasActivePlayback || pendingCarPlayResume != nil, let available = remoteTrackAvailability?(),
              (offset == -1 && available.previous) || (offset == 1 && available.next) else { return }
        onRemoteTrackChange?(offset)
    }

    private func updateRemoteSeekCommands() {
        let enabled = hasActivePlayback && canSeek
        let center = MPRemoteCommandCenter.shared()
        center.changePlaybackPositionCommand.isEnabled = enabled
        // CarPlay Now Playing chooses interval buttons over track navigation.
        // Its video receiver seeks the media timeline independently.
        center.skipBackwardCommand.isEnabled = enabled && !carPlayConnected
        center.skipForwardCommand.isEnabled = enabled && !carPlayConnected
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let seekTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, seekTarget))
        for (command, direction) in [(center.skipBackwardCommand, -1.0), (center.skipForwardCommand, 1.0)] {
            command.preferredIntervals = [10]
            let target = command.addTarget { [weak self] event in
                guard let event = event as? MPSkipIntervalCommandEvent,
                      event.interval.isFinite, event.interval > 0 else { return .commandFailed }
                let offset = direction * event.interval
                Task { @MainActor in self?.seek(by: offset) }
                return .success
            }
            remoteTargets.append((command, target))
        }
        for (command, action) in [(center.playCommand, 0), (center.pauseCommand, 1), (center.togglePlayPauseCommand, 2), (center.stopCommand, 3)] {
            command.isEnabled = action != 1 || pendingCarPlayResume == nil
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.hasActivePlayback || self.pendingCarPlayResume != nil else { return }
                    if action == 0 { self.resume() }
                    else if action == 1 { if self.hasActivePlayback { self.pause() } }
                    else if action == 2 { self.togglePlayPause() }
                    else if let onRemoteStop = self.onRemoteStop { onRemoteStop() }
                    else { self.stop() }
                }
                return .success
            }
            remoteTargets.append((command, target))
        }
        for (command, offset) in [(center.previousTrackCommand, -1), (center.nextTrackCommand, 1)] {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in self?.changeTrack(offset) }
                return .success
            }
            remoteTargets.append((command, target))
        }
        updateRemoteTrackCommands()
        updateRemoteSeekCommands()
    }

    private func fail(_ message: String, reason: DiagnosticReason, failure: DiagnosticFailure? = nil,
                      expectedPlaybackID: UUID? = nil) {
        guard expectedPlaybackID == nil || expectedPlaybackID == playbackID else { return }
        if carPlayConnected {
            CarPlayPlaybackTrace.record("failure \(reason.rawValue) \(failure?.family.rawValue ?? "none"):\(failure?.code ?? 0)")
        }
        // Preserve the original source and timeline. The receiver sometimes
        // cannot read a provider URL/cookie that works on the phone (-1102).
        // Retry through a bounded phone-side HTTP relay exactly once.
        let accessFailure = failure?.contains(family: .url, code: URLError.noPermissionsToReadFile.rawValue) == true
        let externalAssetFailure = failure?.contains(family: .avFoundation, code: AVError.externalPlaybackNotSupportedForAsset.rawValue) == true
        let decodeFailure = failure?.contains(family: .avFoundation, code: AVError.fileFormatNotRecognized.rawValue) == true ||
            failure?.contains(family: .avFoundation, code: AVError.decoderNotFound.rawValue) == true ||
            failure?.contains(family: .avFoundation, code: AVError.decodeFailed.rawValue) == true
        if reason == .playback, usesSystemCarPlayVideo, let request,
           externalAssetFailure || decodeFailure {
            if carPlayBridge == nil || carPlayBridge?.canRetryTranscoding == true {
                startCarPlayBridge(url: request.url, position: request.live ? 0 : currentTime, attemptID: playbackID,
                                   forceTranscode: carPlayBridge != nil)
                return
            }
        }
        if accessFailure || externalAssetFailure, reason == .playback, usesSystemCarPlayVideo, let request,
           !request.url.isFileURL, compatibility == nil, casting == nil, mediaRelay == nil, carPlayBridge == nil {
            var values = DiagnosticValues()
            values.reason = reason; values.failure = failure
            onDiagnostic?(.failure, values)
            do {
                try startRelayedPlayback(url: request.url,
                    position: request.live ? 0 : currentTime, attemptID: playbackID)
                return
            } catch { /* Report the original error if a relay cannot be prepared. */ }
        }
        // A file may have started on the phone before an external route was
        // selected. Recover this specific rejection once, without changing the
        // selected content or repeatedly retrying an unsupported receiver format.
        if externalAssetFailure || accessFailure,
           let request, request.url.isFileURL, request.presentation == .video,
           compatibility == nil, casting == nil, personalMediaServer == nil, carPlayBridge == nil,
           !usesOwnedVideoDisplay, !playsOnPhone {
            do {
                try startLocalExternalPlayback(file: request.url, position: currentTime, attemptID: playbackID)
                return
            } catch { /* Preserve the original playback failure when the file cannot be served. */ }
        }
        measurement.finish(failed: true)
        if let failure { AppMeasurement.shared.failure(.playbackError, failure: failure) }
        // A failed VLC input does not reconnect merely by waiting in .error.
        // Reopen a live network source once, after releasing the previous input.
        // Channel selection/Stop cancels this task and invalidates its identity.
        if let retry = request, retry.live, !retry.url.isFileURL, !retry.requiresExternalPlayback, !usesSystemCarPlayVideo,
           reason == .playback || reason == .unavailable || (retry.lowLatency && reason == .interrupted),
           tvDevice == nil, !hasRemoteVideoOutput || retry.lowLatency, liveRecoveryAttempt < (retry.lowLatency ? 3 : 1) {
            let attempt = liveRecoveryAttempt + 1
            let paused = pauseRequested
            stop(deactivateAudioSession: false)
            request = retry
            pauseRequested = paused
            requestedLive = true; isLive = true
            liveRecoveryAttempt = attempt
            state = .loading
            let id = playbackID
            liveRecoveryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(retry.lowLatency ? 150 : 750)) } catch { return }
                guard let self, self.playbackID == id else { return }
                self.liveRecoveryTask = nil
                do {
                    try self.play(url: retry.url, preserveSourceAudio: retry.preserveSourceAudio,
                        muted: retry.muted, requiresExternalPlayback: retry.requiresExternalPlayback,
                        title: retry.title, live: true, presentation: retry.presentation,
                        useCompatibility: retry.useCompatibility, startPaused: self.pauseRequested, recoveryAttempt: attempt,
                        lowLatency: retry.lowLatency, artworkURL: retry.artworkURL)
                } catch {
                    self.liveRecoveryAttempt = attempt
                    self.fail(message, reason: reason, failure: DiagnosticFailure(error))
                }
            }
            return
        }
        let retry = request
        let position = currentTime
        let live = isLive
        let paused = state == .paused || pauseRequested
        let displayedMessage: String
        if usesSystemCarPlayVideo && (accessFailure || externalAssetFailure || mediaRelay != nil) {
            displayedMessage = displayConnection.failureMessage
        } else { displayedMessage = message }
        stop()
        request = retry
        currentTime = position
        isLive = live
        pauseRequested = paused
        errorMessage = displayedMessage
        state = .failed
        onFailure?(displayedMessage)
        var values = DiagnosticValues()
        values.reason = reason
        values.failure = failure
        onDiagnostic?(.failure, values)
    }

    private func recordAudioRoute() {
        airPlayName = AVAudioSession.sharedInstance().currentRoute.outputs.first { $0.portType == .airPlay }?.portName
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

    private func recordPlaybackSource(url: URL, engine: DiagnosticValues.Engine, transport: DiagnosticValues.Transport) {
        var values = DiagnosticValues()
        values.engine = engine; values.transport = transport
        switch url.pathExtension.lowercased() {
        case "m3u8": values.mediaFormat = .hls
        case "mp4", "m4v", "mov": values.mediaFormat = .mp4
        case "mkv": values.mediaFormat = .mkv
        case "webm": values.mediaFormat = .webm
        case "avi": values.mediaFormat = .avi
        case "ts": values.mediaFormat = .ts
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus": values.mediaFormat = .audio
        default: values.mediaFormat = .other
        }
        onDiagnostic?(.playbackRequested, values)
    }
}
