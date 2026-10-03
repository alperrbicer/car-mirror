import UIKit
import Combine
import AVFoundation
@preconcurrency import VLCKit

/// MKV/WebM playback uses VideoLAN; HLS and Apple-native media stay on AVPlayer.
@MainActor
final class CompatibilityPlayback: NSObject, @preconcurrency VLCMediaPlayerDelegate, @preconcurrency VLCPictureInPictureMediaControlling {
    let mediaPlayer = VLCMediaPlayer(options: ["--quiet", "--no-video-title-show"])
    lazy var videoView: CompatibilityVideoSurface = {
        let view = CompatibilityVideoSurface()
        view.owner = self
        view.backgroundColor = .black
        return view
    }()
    var onState: ((PlaybackController.State) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var onFinished: (() -> Void)?
    var onRestore: (() -> Void)?
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
        if videoView.superview !== selected {
            videoView.removeFromSuperview()
            videoView.translatesAutoresizingMaskIntoConstraints = true
            videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            videoView.frame = selected.bounds
            selected.addSubview(videoView)
        } else if videoView.frame != selected.bounds {
            videoView.frame = selected.bounds
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
        controller.stateChangeEventHandler = { [weak self] started in
            Task { @MainActor in
                guard let self else { return }
                self.pipActive = started
                if !started {
                    self.videoView.restoreAfterPictureInPicture()
                    if self.active { self.onRestore?() }
                }
            }
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
final class CompatibilityVideoSurface: UIView, @preconcurrency VLCPictureInPictureDrawable {
    weak var owner: CompatibilityPlayback?
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        // VLC may create its renderer while this drawable still belongs to the
        // 88x50 preview (or has no bounds yet). Keep it sized to the current host.
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subview.frame = bounds
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews where subview.frame != bounds { subview.frame = bounds }
    }
    func restoreAfterPictureInPicture() {
        // PiP can leave its temporary clipping on VLC's sample-buffer layer.
        // Clear it only after didStop, so the system's return animation finishes.
        // The surrounding player card owns the four matching rounded corners.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        restoreVideoClipping(in: layer)
        setNeedsLayout()
        layoutIfNeeded()
        CATransaction.commit()
    }
    private func restoreVideoClipping(in layer: CALayer) {
        if layer is AVSampleBufferDisplayLayer {
            layer.removeAnimation(forKey: "cornerRadius")
            layer.removeAnimation(forKey: "maskedCorners")
            layer.removeAnimation(forKey: "mask")
            layer.mask = nil
            layer.cornerRadius = 0
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                   .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        for sublayer in layer.sublayers ?? [] { restoreVideoClipping(in: sublayer) }
    }
    func mediaController() -> any VLCPictureInPictureMediaControlling { owner! }
    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        { [weak self] controller in
            guard let controller else { return }
            Task { @MainActor in self?.owner?.configurePiP(controller) }
        }
    }
}
