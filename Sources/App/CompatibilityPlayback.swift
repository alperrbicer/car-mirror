import UIKit
import Combine
import AVFoundation
import AVKit
@preconcurrency import VLCKit

/// MKV/WebM playback uses VideoLAN; HLS and Apple-native media stay on AVPlayer.
@MainActor
final class CompatibilityPlayback: NSObject, @preconcurrency VLCMediaPlayerDelegate, @preconcurrency VLCPictureInPictureMediaControlling {
    let mediaPlayer = VLCMediaPlayer(options: ["--quiet", "--no-video-title-show"])
    lazy var videoView: CompatibilityVideoSurface = {
        let view = CompatibilityVideoSurface()
        view.owner = self
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }()
    var onState: ((PlaybackController.State) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var onTracksChanged: (() -> Void)?
    var onFinished: (() -> Void)?
    var onRestore: ((@escaping (Bool) -> Void) -> Void)?
    var onPiPReady: (() -> Void)?
    var onPiPStarted: (() -> Void)?
    var onPiPWillStop: (() -> Void)?
    var onPiPStopped: (() -> Void)?
    private var active = false
    private var stoppingRetention: CompatibilityPlayback?
    private var hasPlayed = false
    private var videoHosts: [WeakVideoHost] = []
    private struct SeekRequest {
        var target: Double
        var completions: [() -> Void]
    }
    private var queuedSeek: SeekRequest?
    private var activeSeekID: UUID?
    private var activeSeekCompletions: [() -> Void] = []
    private var seekTask: Task<Void, Never>?
    private var seekTimeoutTask: Task<Void, Never>?
    var pip: (any VLCPictureInPictureWindowControlling)?
    private(set) var pipActive = false
    var pipStarting: Bool { (pip as? CompatibilityPictureInPicture)?.starting == true }
    var pipPossible: Bool { (pip as? CompatibilityPictureInPicture)?.controller.isPictureInPicturePossible ?? (pip != nil) }

    override init() {
        super.init()
        mediaPlayer.delegate = self
        mediaPlayer.drawable = videoView
    }
    func open(_ url: URL) {
        active = true; hasPlayed = false
        let media = VLCMedia(url: url)
        if !url.isFileURL && url.pathExtension.lowercased() == "mkv" {
            // Use the Matroska cue index for remote seeks instead of scanning
            // and decoding all preceding clusters over the network.
            media?.addOption(":demux=mkv_trusted")
        }
        mediaPlayer.media = media
        mediaPlayer.play()
    }
    func stop() {
        active = false
        videoView.prepareForPictureInPicture()
        seekTask?.cancel(); seekTask = nil
        seekTimeoutTask?.cancel(); seekTimeoutTask = nil
        activeSeekID = nil
        let completions = activeSeekCompletions + (queuedSeek?.completions ?? [])
        activeSeekCompletions = []; queuedSeek = nil
        completions.forEach { $0() }
        if mediaPlayer.state != .stopped && mediaPlayer.state != .nothingSpecial { stoppingRetention = self }
        pip?.stopPictureInPicture()
        mediaPlayer.stop()
    }
    func play() { guard active else { return }; mediaPlayer.play() }
    func pause() { mediaPlayer.pause() }
    func startPictureInPicture() {
        guard pipPossible, !pipActive, !pipStarting else { return }
        videoView.prepareForPictureInPicture()
        pip?.startPictureInPicture()
    }
    fileprivate func preparePictureInPicture(with layer: AVSampleBufferDisplayLayer) {
        guard active else { return }
        if let current = pip as? CompatibilityPictureInPicture {
            guard current.controller.contentSource?.sampleBufferDisplayLayer !== layer,
                  !pipActive, !current.starting else { return }
        } else if pip != nil { return }
        guard let controller = CompatibilityPictureInPicture(engine: self, layer: layer) else { return }
        configurePiP(controller)
    }
    func preparePictureInPictureReturn(completion: @escaping (Bool) -> Void) {
        refreshVideoHost()
        PlayerVideoReturnLayout.prepare(videoView, completion: completion)
    }
    func layoutVideoForPictureInPictureReturn() {
        refreshVideoHost()
        videoView.window?.layoutIfNeeded()
        videoView.setNeedsLayout()
        videoView.layoutIfNeeded()
    }
    var audioChoices: [PlaybackTrack] { choices(mediaPlayer.audioTracks) }
    var subtitleChoices: [PlaybackTrack] { choices(mediaPlayer.textTracks) }
    private func choices(_ tracks: [VLCMediaPlayer.Track]) -> [PlaybackTrack] {
        tracks.map { PlaybackTrack(id: $0.trackId, title: $0.trackName, isSelected: $0.isSelected) }
    }
    func selectAudioTrack(_ id: String) {
        guard active, let track = mediaPlayer.audioTracks.first(where: { $0.trackId == id }) else { return }
        track.isSelectedExclusively = true
        onTracksChanged?()
    }
    func selectSubtitleTrack(_ id: String?) {
        guard active else { return }
        if let id {
            guard let track = mediaPlayer.textTracks.first(where: { $0.trackId == id }) else { return }
            mediaPlayer.selectTextTracks([track])
        } else { mediaPlayer.deselectAllTextTracks() }
        onTracksChanged?()
    }
    func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) { tracksChanged() }
    func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) { tracksChanged() }
    func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) { tracksChanged() }
    func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) { tracksChanged() }
    private func tracksChanged() {
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.onTracksChanged?()
        }
    }
    func setVideoFill(_ fillsFrame: Bool) {
        let mode: VLCMediaPlayer.VideoFitMode = fillsFrame ? .larger : .smaller
        if mediaPlayer.videoFitMode != mode { mediaPlayer.videoFitMode = mode }
    }
    // VLC has one drawable. A retained source-list preview must never take it
    // back from the player when SwiftUI refreshes the playback time or metadata.
    fileprivate func updateVideoHost(_ host: CompatibilityVideoHost) {
        videoHosts.removeAll { $0.value == nil }
        if host.window != nil && !videoHosts.contains(where: { $0.value === host }) {
            videoHosts.append(WeakVideoHost(host))
        }
        refreshVideoHost()
    }
    fileprivate func removeVideoHost(_ host: CompatibilityVideoHost) {
        videoHosts.removeAll { $0.value == nil || $0.value === host }
        refreshVideoHost()
    }
    private func refreshVideoHost() {
        let hosts = videoHosts.compactMap(\.value).filter { $0.isReadyForVideo }
        // Prefer the most recently mounted host when two destinations overlap
        // during navigation. Updates to older hosts do not change that order.
        let selected = hosts.reversed().max { $0.role.rawValue < $1.role.rawValue }
        guard let selected else {
            videoView.removeFromSuperview()
            return
        }
        let frame = PlayerVideoGeometry.frame(size: mediaPlayer.videoSize, in: selected.bounds, fillsFrame: selected.fillsFrame)
        if videoView.superview !== selected {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoView.removeFromSuperview()
            videoView.translatesAutoresizingMaskIntoConstraints = true
            videoView.autoresizingMask = []
            videoView.frame = frame
            selected.addSubview(videoView)
            CATransaction.commit()
        } else if videoView.frame != frame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoView.frame = frame
            CATransaction.commit()
        }
        setVideoFill(selected.fillsFrame)
    }
    private final class WeakVideoHost {
        weak var value: CompatibilityVideoHost?
        init(_ value: CompatibilityVideoHost) { self.value = value }
    }
    func seek(by offset: Int64, completion: @escaping () -> Void) {
        seek(to: Double(mediaTime() + offset) / 1000, completion: completion)
    }
    func mediaLength() -> Int64 { mediaPlayer.media?.length.value?.int64Value ?? 0 }
    func mediaTime() -> Int64 { mediaPlayer.time.value?.int64Value ?? 0 }
    func isMediaSeekable() -> Bool { mediaPlayer.isSeekable }
    func isMediaPlaying() -> Bool { mediaPlayer.isPlaying }
    func seek(to seconds: Double, completion: @escaping () -> Void = {}) {
        guard active, seconds.isFinite, isMediaSeekable() else { completion(); return }
        let target = min(max(0, seconds), Double(mediaLength()) / 1000)
        if queuedSeek != nil {
            queuedSeek?.target = target
            queuedSeek?.completions.append(completion)
        } else {
            queuedSeek = SeekRequest(target: target, completions: [completion])
        }
        scheduleSeek()
    }
    private func scheduleSeek() {
        guard activeSeekID == nil else { return }
        seekTask?.cancel()
        // VLCKit keeps a single completion slot. Concurrent jumps can overwrite
        // it and report an older seek as completion of the newest request.
        // Merge quick button taps and execute only one jump at a time.
        seekTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, self.active, let request = self.queuedSeek else { return }
            self.queuedSeek = nil
            self.seekTask = nil
            let id = UUID()
            self.activeSeekID = id
            self.activeSeekCompletions = request.completions
            let offset = Int64(request.target * 1000) - self.mediaTime()
            // A no-op need not emit a VLC seek-completion event.
            if abs(offset) <= 50 { self.finishSeek(id); return }
            self.seekTimeoutTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.active, self.activeSeekID == id else { return }
                // Do not leave the timeline/queued requests waiting indefinitely.
                self.stop()
                self.onState?(.failed)
            }
            let accepted = self.mediaPlayer.jump(withOffset: Int32(clamping: offset)) { [weak self] in
                Task { @MainActor in self?.finishSeek(id) }
            }
            if !accepted { self.finishSeek(id) }
        }
    }
    private func finishSeek(_ id: UUID) {
        guard activeSeekID == id else { return }
        activeSeekID = nil
        seekTimeoutTask?.cancel(); seekTimeoutTask = nil
        let completions = activeSeekCompletions
        activeSeekCompletions = []
        completions.forEach { $0() }
        if queuedSeek != nil { scheduleSeek() }
    }
    func configurePiP(_ controller: any VLCPictureInPictureWindowControlling) {
        pip = controller
        controller.stateChangeEventHandler = { [weak self, weak controller] started in
            let update = { @MainActor [weak self, weak controller] in
                guard let self, let controller, self.pip === controller else { return }
                self.pictureInPictureStateChanged(started)
            }
            if Thread.isMainThread { MainActor.assumeIsolated { update() } }
            else { Task { @MainActor in update() } }
        }
        onPiPReady?()
    }
    private func pictureInPictureStateChanged(_ started: Bool) {
        pipActive = started
        if started {
            guard active else { pip?.stopPictureInPicture(); return }
            videoView.prepareForPictureInPicture()
            onPiPStarted?()
        } else {
            if active { videoView.restoreAfterPictureInPicture() }
            onPiPStopped?()
        }
    }
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        // Delegate callbacks can already be queued when a channel is replaced.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.mediaPlayer.state == .stopped {
                self.stoppingRetention = nil
                if !self.active { self.mediaPlayer.drawable = nil; self.pip = nil; return }
            }
            guard self.active else { return }
            self.refreshVideoHost()
            self.onTracksChanged?()
            switch self.mediaPlayer.state {
            case .opening: self.onState?(.loading)
            case .playing: self.hasPlayed = true; self.onState?(.playing)
            case .paused: self.onState?(.paused)
            case .error: self.onState?(.failed)
            case .stopped: if self.hasPlayed { self.onFinished?() }
            default: break
            }
            self.pip?.invalidatePlaybackState()
        }
    }
    func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.refreshVideoHost()
            self.onTime?(Double(self.mediaTime()) / 1000, Double(self.mediaLength()) / 1000)
        }
    }
    func mediaPlayerLengthChanged(_ length: Int64) {
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.onTime?(Double(self.mediaTime()) / 1000, Double(self.mediaLength()) / 1000)
            self.pip?.invalidatePlaybackState()
        }
    }
}

/// Keep the PiP source at the rendered picture's bounds, rather than including
/// the surrounding letterbox. The host remains black and owns the gestures.
enum PlayerVideoGeometry {
    static func frame(size: CGSize, in bounds: CGRect, fillsFrame: Bool) -> CGRect {
        guard !fillsFrame, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        return AVMakeRect(aspectRatio: size, insideRect: bounds)
    }
}

/// Mounts the shared VLC surface only after UIKit has a window and valid bounds.
/// The engine arbitrates ownership across previews, inline and full-screen video.
@MainActor
final class CompatibilityVideoHost: UIView {
    enum Role: Int { case preview, inline, fullscreen, external }
    private var engine: CompatibilityPlayback?
    fileprivate private(set) var role: Role = .inline
    fileprivate private(set) var fillsFrame = false
    fileprivate var isReadyForVideo: Bool {
        window != nil && !isHidden && bounds.width > 0 && bounds.height > 0
    }
    func configure(engine: CompatibilityPlayback, role: Role, fillsFrame: Bool) {
        if self.engine !== engine {
            self.engine?.removeVideoHost(self)
            self.engine = engine
        }
        self.role = role
        self.fillsFrame = fillsFrame
        backgroundColor = .black
        clipsToBounds = true
        engine.updateVideoHost(self)
    }
    func detach() {
        engine?.removeVideoHost(self)
        engine = nil
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { engine?.removeVideoHost(self) }
        else { engine?.updateVideoHost(self) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        engine?.updateVideoHost(self)
    }
}

@MainActor
final class CompatibilityVideoSurface: UIView {
    weak var owner: CompatibilityPlayback?
    private lazy var videoClipping = PlayerVideoClipping(root: layer)
    // Temporarily allow capture at the user's request to diagnose PiP corner
    // transitions. Keep it available while validating the fix on the device.
    var captureProtectionEnabled = false {
        didSet { protectVideoLayers(in: layer) }
    }
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        // VLC may create its renderer while this drawable still belongs to the
        // 88x50 preview (or has no bounds yet). Keep it sized to the current host.
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subview.frame = bounds
        protectVideoLayers(in: subview.layer)
        videoClipping.repairIfRestored()
        // VLC finishes configuring the renderer after addSubview returns.
        // The app owns AVKit's delegate so restoration can precede PiP's stop.
        DispatchQueue.main.async { [weak self] in self?.preparePictureInPictureSource() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for subview in subviews where subview.frame != bounds { subview.frame = bounds }
        protectVideoLayers(in: layer)
        videoClipping.repairIfRestored()
        CATransaction.commit()
        preparePictureInPictureSource()
    }
    // Public AVFoundation protection applies to decoded video, including PiP.
    // UIKit chrome and unprotected AVPlayerLayer content remain capturable.
    func protectVideoLayers(in layer: CALayer) {
        if let video = layer as? AVSampleBufferDisplayLayer { video.preventsCapture = captureProtectionEnabled }
        for child in layer.sublayers ?? [] { protectVideoLayers(in: child) }
    }
    func restoreAfterPictureInPicture() {
        videoClipping.restore()
        setNeedsLayout()
        layoutIfNeeded()
    }
    func prepareForPictureInPicture() { videoClipping.suspend() }
    private func preparePictureInPictureSource() {
        func videoLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
            if let video = layer as? AVSampleBufferDisplayLayer { return video }
            return (layer.sublayers ?? []).reversed().lazy.compactMap { videoLayer(in: $0) }.first
        }
        if let video = videoLayer(in: layer) { owner?.preparePictureInPicture(with: video) }
    }
}

/// VLCKit's built-in PiP bridge doesn't forward UI restoration or willStop.
/// Owning this public AVKit controller prepares the target before animating back.
/// The drawable deliberately does not adopt VLCPictureInPictureDrawable: there
/// must be only one PiP controller for the existing VLC sample-buffer layer.
@MainActor
private final class CompatibilityPictureInPicture: NSObject, @preconcurrency VLCPictureInPictureWindowControlling,
    @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    private let layer: AVSampleBufferDisplayLayer
    private(set) lazy var controller = AVPictureInPictureController(
        contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
    var stateChangeEventHandler: ((Bool) -> Void)?
    private weak var engine: CompatibilityPlayback?
    private var possibleObservation: NSKeyValueObservation?
    private(set) var starting = false
    private var stopping = false

    init?(engine: CompatibilityPlayback, layer: AVSampleBufferDisplayLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }
        self.engine = engine
        self.layer = layer
        super.init()
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.engine?.onPiPReady?() }
        }
        invalidatePlaybackState()
    }
    func startPictureInPicture() {
        guard controller.isPictureInPicturePossible, !controller.isPictureInPictureActive, !starting, !stopping else { return }
        controller.startPictureInPicture()
    }
    func stopPictureInPicture() {
        guard !stopping else { return }
        controller.stopPictureInPicture()
    }
    func invalidatePlaybackState() {
        controller.requiresLinearPlayback = engine?.isMediaSeekable() != true
        controller.invalidatePlaybackState()
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = true
        stopping = false
        engine?.videoView.prepareForPictureInPicture()
        invalidatePlaybackState()
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = false
        stateChangeEventHandler?(true)
    }
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopping = true
        engine?.onPiPWillStop?()
        engine?.layoutVideoForPictureInPictureReturn()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        starting = false
        stopping = false
        stateChangeEventHandler?(false)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        starting = false
        stopping = false
        stateChangeEventHandler?(false)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        stopping = true
        guard let restore = engine?.onRestore else { stopping = false; completionHandler(false); return }
        restore { [weak self] restored in
            if !restored { self?.stopping = false }
            completionHandler(restored)
        }
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard let engine, engine.isMediaPlaying() != playing else { return }
        if playing { engine.play() } else { engine.pause() }
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        engine?.isMediaPlaying() != true
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        guard let engine else { return .invalid }
        guard engine.isMediaSeekable(), engine.mediaLength() > 0 else {
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        let layerTime = layer.controlTimebase.map { CMTimebaseGetTime($0) }
            ?? CMClockGetTime(CMClockGetHostTimeClock())
        return CMTimeRange(start: layerTime - CMTime(value: engine.mediaTime(), timescale: 1000),
                           duration: CMTime(value: engine.mediaLength(), timescale: 1000))
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) {
        guard let engine, skipInterval.seconds.isFinite else { completion(); return }
        engine.seek(to: Double(engine.mediaTime()) / 1000 + skipInterval.seconds, completion: completion)
    }
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }
}

/// SwiftUI's onAppear can precede the source view's layout. Complete restoration
/// only after the existing source has a window and its layout has been committed.
@MainActor
enum PlayerVideoReturnLayout {
    static func prepare(_ view: UIView, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { completion(false); return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak view, weak window] in
                DispatchQueue.main.async {
                    guard let view, let window, view.window === window,
                          !view.isHidden, view.bounds.width > 0, view.bounds.height > 0 else {
                        completion(false); return
                    }
                    completion(true)
                }
            }
            UIView.performWithoutAnimation {
                window.layoutIfNeeded()
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
            CATransaction.commit()
        }
    }
}

/// Repair only the owned video subtree, including ordinary CALayer wrappers
/// and renderer children. AVKit's transition clipping is not limited to the
/// AVPlayerLayer / AVSampleBufferDisplayLayer itself.
@MainActor
final class PlayerVideoClipping {
    private weak var root: CALayer?
    private var restored = false
    private var repairing = false
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var displayLink: CADisplayLink?
    private var repairUntil: CFTimeInterval = 0
    private let tickTarget = TickTarget()
    private let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                           .layerMinXMaxYCorner, .layerMaxXMaxYCorner]

    init(root: CALayer) { self.root = root; tickTarget.owner = self }
    deinit { displayLink?.invalidate() }

    func suspend() {
        restored = false
        displayLink?.invalidate(); displayLink = nil
        observations.removeAll()
    }
    func restore() {
        suspend()
        restored = true
        repairIfRestored()
        // Explicit animations don't publish KVO changes. Inspect those during
        // the return handoff as well, including groups with arbitrary keys.
        repairUntil = CACurrentMediaTime() + 2
        let link = CADisplayLink(target: tickTarget, selector: #selector(TickTarget.tick))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    func repairIfRestored() {
        guard restored, !repairing, let root else { return }
        repairing = true
        defer { repairing = false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        repair(in: root)
        CATransaction.commit()
    }
    private func containsVideo(_ layer: CALayer) -> Bool {
        layer is AVSampleBufferDisplayLayer || layer is AVPlayerLayer ||
            (layer.sublayers ?? []).contains(where: containsVideo)
    }
    private func repair(in layer: CALayer, insideVideo: Bool = false) {
        guard insideVideo || containsVideo(layer) else { return }
        observe(layer)
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key) else { continue }
            let (remaining, changed) = withoutClipping(animation)
            if changed {
                layer.removeAnimation(forKey: key)
                if let remaining { layer.add(remaining, forKey: key) }
            }
        }
        if layer.mask != nil { layer.mask = nil }
        if layer.cornerRadius != 0 { layer.cornerRadius = 0 }
        if layer.maskedCorners != allCorners { layer.maskedCorners = allCorners }
        let isVideo = insideVideo || layer is AVSampleBufferDisplayLayer || layer is AVPlayerLayer
        for child in layer.sublayers ?? [] { repair(in: child, insideVideo: isVideo) }
    }
    private func withoutClipping(_ animation: CAAnimation) -> (CAAnimation?, Bool) {
        if let property = animation as? CAPropertyAnimation, let path = property.keyPath,
           ["cornerRadius", "maskedCorners", "cornerCurve", "mask"].contains(path) || path.hasPrefix("mask.") {
            return (nil, true)
        }
        guard let group = animation as? CAAnimationGroup else { return (animation, false) }
        let children = (group.animations ?? []).map(withoutClipping)
        guard children.contains(where: { $0.1 }) else { return (animation, false) }
        let remaining = children.compactMap(\.0)
        guard !remaining.isEmpty else { return (nil, true) }
        let copy = group.copy() as! CAAnimationGroup
        copy.animations = remaining
        return (copy, true)
    }
    private func observe(_ layer: CALayer) {
        let id = ObjectIdentifier(layer)
        guard observations[id] == nil else { return }
        observations[id] = [
            layer.observe(\.cornerRadius) { [weak self] _, _ in self?.clippingChanged() },
            layer.observe(\.maskedCorners) { [weak self] _, _ in self?.clippingChanged() },
            layer.observe(\.mask) { [weak self] _, _ in self?.clippingChanged() },
            layer.observe(\.sublayers) { [weak self] _, _ in self?.clippingChanged() }
        ]
    }
    nonisolated private func clippingChanged() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { repairIfRestored() }
        } else { Task { @MainActor [weak self] in self?.repairIfRestored() } }
    }
    private func tick() {
        repairIfRestored()
        if root == nil || CACurrentMediaTime() >= repairUntil {
            displayLink?.invalidate(); displayLink = nil
        }
    }
    @MainActor
    private final class TickTarget: NSObject {
        weak var owner: PlayerVideoClipping?
        @objc func tick() { owner?.tick() }
    }
}
