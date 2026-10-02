import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    enum Destination { case preview, carPlay }
    let player = AVPlayer()
    @Published private(set) var externalPlaybackActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private(set) var destination: Destination?
    private var externalObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var playingObservation: NSKeyValueObservation?
    private var activatedAudioSession = false

    init() {
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.isMuted = true
        externalObservation = player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            let active = player.isExternalPlaybackActive
            Task { @MainActor in self?.externalPlaybackActive = active }
        }
        playingObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let active = player.timeControlStatus == .playing
            Task { @MainActor in self?.isPlaying = active }
        }
    }

    func play(url: URL, destination: Destination) throws {
        stop()
        errorMessage = nil
        if destination == .carPlay {
            // Real video playback only. Mixing avoids deliberately taking over source-app audio.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
            activatedAudioSession = true
        }
        self.destination = destination
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            guard let item, item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Canlı yayın oynatılamadı."
            Task { @MainActor in self?.errorMessage = message }
        }
        player.replaceCurrentItem(with: item)
        if destination == .carPlay {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: "iPhone ekranı",
                MPMediaItemPropertyArtist: "CarMirror",
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0
            ]
        }
        player.play()
    }

    func stop() {
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if destination == .carPlay { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        destination = nil
        isPlaying = false
        if activatedAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            activatedAudioSession = false
        }
    }
}
