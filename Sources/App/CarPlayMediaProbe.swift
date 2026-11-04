import Foundation
@preconcurrency import VLCKit

enum CarPlayPlaybackTrace {
    static func record(_ event: String) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace") {
            NSLog("[Mirivo.CarPlay.Startup] %@ uptime=%.3f", event, ProcessInfo.processInfo.systemUptime)
        }
        #endif
    }
}

/// Pre-parsing is not playback: remote providers can omit preparse metadata
/// while VLC can still open the media. Read the actual demuxed tracks silently.
@MainActor
final class CarPlayMediaProbe: NSObject, @preconcurrency VLCMediaPlayerDelegate {
    struct Result {
        let videoID: String
        let videoCodec: UInt32
        let audioCodecs: [UInt32]
        let duration: Double
    }

    private let player = VLCMediaPlayer(options: ["--quiet", "--no-video-title-show", "--vout=dummy", "--aout=dummy"])
    private var timeout: Task<Void, Never>?
    private var trackRead: Task<Void, Never>?
    private var active = false
    private var result: Result?
    private var failure: Error?
    private var stoppingRetention: CarPlayMediaProbe?
    var onComplete: ((Swift.Result<Result, Error>) -> Void)?

    func start(_ url: URL) {
        guard !active else { return }
        guard let media = VLCMedia(url: url) else { onComplete?(.failure(URLError(.badURL))); onComplete = nil; return }
        active = true
        player.delegate = self
        player.enableCarPlayDebugLogging()
        media.addOption(":network-caching=150")
        media.addOption(":file-caching=150")
        if url.pathExtension.lowercased() == "mkv" { media.addOption(":demux=mkv_trusted") }
        player.media = media
        player.play()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.finish(error: URLError(.timedOut))
        }
    }

    func mediaPlayerStateChanged(_ state: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .stopped, !self.active { self.didStop(); return }
            guard self.active else { return }
            if self.player.state == .error { self.finish(error: URLError(.cannotDecodeContentData)) }
            if self.player.state == .playing { self.readTracks() }
        }
    }

    private func readTracks() {
        guard active, trackRead == nil else { return }
        trackRead = Task { [weak self] in
            // Track-added callbacks can follow Playing. Wait for the complete
            // selected program, then release its connection before conversion.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, self.active else { return }
            self.trackRead = nil
            guard let video = self.player.videoTracks.first(where: \.isSelected) ?? self.player.videoTracks.first else {
                self.readTracks(); return
            }
            self.result = Result(videoID: video.trackId, videoCodec: video.codec,
                audioCodecs: self.player.audioTracks.map(\.codec),
                duration: max(0, Double(self.player.media?.length.intValue ?? 0) / 1_000))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace") {
                print("[Mirivo.CarPlay] probe-ready video=\(video.trackId) codec=\(video.codec) audio=\(self.player.audioTracks.map(\.codec))")
            }
            #endif
            self.finish(error: nil)
        }
    }

    private func finish(error: Error?) {
        guard active else { return }
        failure = error
        active = false
        timeout?.cancel(); timeout = nil
        trackRead?.cancel(); trackRead = nil
        if player.state == .stopped || player.state == .nothingSpecial { didStop() }
        else { stoppingRetention = self; player.stop() }
    }

    private func didStop() {
        guard !active else { finish(error: URLError(.cannotDecodeContentData)); return }
        let callback = onComplete
        onComplete = nil
        if let result { callback?(.success(result)) }
        else if let failure { callback?(.failure(failure)) }
        stoppingRetention = nil
    }

    func stop() {
        onComplete = nil
        finish(error: CancellationError())
    }
}

extension VLCMediaPlayer {
    func enableCarPlayDebugLogging() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace") {
            libraryInstance.loggers = [CarPlayVLCLogger()]
        }
        #endif
    }
}

#if DEBUG
private final class CarPlayVLCLogger: NSObject, VLCLogging {
    var level = VLCLogLevel(rawValue: 0)!

    func handleMessage(_ message: String, logLevel: VLCLogLevel, context: VLCLogContext?) {
        // Device-only, opt-in development output. Never print provider URLs,
        // which can contain credentials in both the authority and the path.
        let redacted = message.replacingOccurrences(of: #"(?i)https?://[^\s\"']+"#,
            with: "<source>", options: .regularExpression)
        print("[Mirivo.CarPlay.VLC.\(context?.module ?? "unknown")] \(redacted.prefix(300))")
    }
}
#endif
