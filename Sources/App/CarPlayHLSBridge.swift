import Foundation
import AVFoundation
@preconcurrency import VLCKit

/// Adapts containers/codecs that AVPlayer cannot send to a system video route.
/// VLC reads the original source; the receiver only sees a bounded, local HLS session.
@MainActor
final class CarPlayHLSBridge: NSObject, @preconcurrency VLCMediaPlayerDelegate {
    private let source: URL
    private let live: Bool
    let startPosition: Double
    private let forceTranscode: Bool
    private var probe: CarPlayMediaProbe?
    private var encoder = VLCMediaPlayer(options: ["--quiet", "--no-video-title-show"])
    private var media: VLCMedia?
    private var server: CarPlayHLSServer?
    private var monitor: Task<Void, Never>?
    private var stopped = false
    private var ready = false
    private var outputStarted = false
    private var encodingBegan = false
    private var producerFinished = false
    private var stoppingRetention: CarPlayHLSBridge?
    private var requestedPause = false
    private var pausePending = false
    private var vodPlaylist: CarPlayVODPlaylist?
    private var vodAddress: URL?
    private var pendingSegments: [Int] = []
    private var nextSegmentToPrefetch: Int?
    private var encodingSegment: Int?
    private var segmentOutput: URL?
    private var vodTranscodesAudio = false
    private var segmentDelegate: SegmentDelegate?
    private(set) var duration: Double = 0
    private(set) var transcodesVideo = false
    private(set) var isVideoOnlyVOD = false
    var canRetryTranscoding: Bool { outputStarted && !transcodesVideo }
    var supportsNativeSeeking: Bool { vodPlaylist != nil }
    var onReady: ((URL) -> Void)?
    var onFailure: ((Error) -> Void)?

    init(source: URL, live: Bool, startPosition: Double, forceTranscode: Bool = false) {
        self.source = source
        self.live = live
        self.startPosition = live ? 0 : max(0, startPosition)
        self.forceTranscode = forceTranscode
        super.init()
        encoder.delegate = self
        encoder.enableCarPlayDebugLogging()
    }

    func start() {
        guard !stopped, probe == nil, !outputStarted else { return }
        CarPlayPlaybackTrace.record("probe-start")
        let probe = CarPlayMediaProbe()
        self.probe = probe
        probe.onComplete = { [weak self, weak probe] result in
            guard let self, let probe, self.probe === probe, !self.stopped else { return }
            self.probe = nil
            switch result {
            case .success(let metadata): self.prepareOutput(metadata)
            case .failure(let error): self.fail(error)
            }
        }
        probe.start(source)
    }

    private func prepareOutput(_ metadata: CarPlayMediaProbe.Result) {
        guard !stopped, !outputStarted else { return }
        CarPlayPlaybackTrace.record("probe-finished")
        guard !metadata.videoID.isEmpty,
              metadata.videoID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 47 }),
              let media = VLCMedia(url: source) else { fail(URLError(.cannotDecodeContentData)); return }
        self.media = media
        if source.pathExtension.lowercased() == "mkv" { media.addOption(":demux=mkv_trusted") }
        outputStarted = true
        duration = live ? 0 : metadata.duration
        // H.264 can be remuxed without decoding. Other video codecs use the
        // device's H.264 encoder so their container extension is never a gate.
        transcodesVideo = forceTranscode || metadata.videoCodec != Self.fourCC("h264")
        let transcodesAudio = forceTranscode || metadata.audioCodecs.contains { $0 != Self.fourCC("mp4a") }
        if !live && duration > 0 {
            isVideoOnlyVOD = metadata.audioCodecs.isEmpty
            vodTranscodesAudio = transcodesAudio
            prepareVOD()
            return
        }
        do {
            let server = try CarPlayHLSServer(vod: !live)
            self.server = server
            server.start(onReady: { [weak self, weak server] url in
                Task { @MainActor in
                    guard let self, let server, self.server === server, !self.stopped else { return }
                    self.beginOutput(media: media, videoID: metadata.videoID, transcodesAudio: transcodesAudio,
                                     server: server, url: url)
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor in self?.fail(error) }
            })
        } catch { fail(error) }
    }

    private func prepareVOD() {
        do {
            let playlist = try CarPlayVODPlaylist(duration: duration, startPosition: startPosition)
            vodPlaylist = playlist
            transcodesVideo = true
            // The receiver can request any part of the finite source timeline.
            let server = try CarPlayHLSServer(vod: true, playlist: playlist)
            self.server = server
            server.onSegmentRequested = { [weak self] index in
                Task { @MainActor in self?.requestSegment(index) }
            }
            server.start(onReady: { [weak self, weak server] address in
                Task { @MainActor in
                    guard let self, let server, self.server === server, !self.stopped else { return }
                    self.vodAddress = address
                    self.requestSegment(playlist.index(at: playlist.startPosition))
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor in self?.fail(error) }
            })
        } catch { fail(error) }
    }

    private func requestSegment(_ index: Int) {
        guard !stopped, let playlist = vodPlaylist, let server, playlist.interval(for: index) != nil else { return }
        nextSegmentToPrefetch = index + 1 < playlist.segmentCount ? index + 1 : nil
        if encodingSegment != index,
           !FileManager.default.fileExists(atPath: server.directory.appendingPathComponent(playlist.name(for: index)).path) {
            pendingSegments.removeAll { $0 == index }
            pendingSegments.insert(index, at: 0)
            if pendingSegments.count > 12 { pendingSegments.removeLast() }
        }
        encodeNextSegment()
    }

    private func encodeNextSegment() {
        guard !stopped, encodingSegment == nil, let playlist = vodPlaylist, let server else { return }
        let index: Int
        if !pendingSegments.isEmpty {
            index = pendingSegments.removeFirst()
        } else {
            guard let next = nextSegmentToPrefetch else { return }
            nextSegmentToPrefetch = nil
            let file = server.directory.appendingPathComponent(playlist.name(for: next))
            guard !FileManager.default.fileExists(atPath: file.path) else { return }
            index = next
        }
        guard let interval = playlist.interval(for: index), let media = VLCMedia(url: source) else {
            fail(URLError(.cannotDecodeContentData)); return
        }
        let output = server.directory.appendingPathComponent("encoding-\(UUID().uuidString).part")
        // Use an independent player and clock for every segment. Reusing VLC's
        // output resources can carry timing from a previously encoded range.
        encoder.delegate = nil
        let player = VLCMediaPlayer(options: ["--quiet", "--no-video-title-show"])
        encoder = player
        let delegate = SegmentDelegate { [weak self, weak player] state in
            guard let self, let player, self.encoder === player else { return }
            self.encoderStateChanged(state)
        }
        segmentDelegate = delegate
        player.delegate = delegate
        player.enableCarPlayDebugLogging()
        encodingSegment = index
        CarPlayPlaybackTrace.record("segment-start \(index)")
        segmentOutput = output
        self.media = media
        if source.pathExtension.lowercased() == "mkv" { media.addOption(":demux=mkv_trusted") }
        media.addOption(":start-time=\(interval.lowerBound)")
        media.addOption(":stop-time=\(interval.upperBound)")
        media.addOption(":no-input-fast-seek")
        media.addOption(":network-caching=300")
        media.addOption(":file-caching=300")
        media.addOption(":no-sout-all")
        media.addOption(":no-sout-keep")
        var conversion: [String] = []
        if transcodesVideo {
            conversion += ["vcodec=h264", "venc=avcodec{codec=h264_videotoolbox,keyint=1,bframes=0}",
                           "vb=4000", "maxwidth=1280", "maxheight=720"]
        }
        if vodTranscodesAudio { conversion += ["acodec=mp4a", "aenc=avcodec{codec=aac}", "ab=160", "channels=2", "samplerate=48000"] }
        let transcode = conversion.isEmpty ? "" : "transcode{\(conversion.joined(separator: ","))}:"
        media.addOption(":sout=#\(transcode)std{access=file,mux=ts,dst='\(output.path)'}")
        encoder.media = media
        encodingBegan = true
        encoder.play()
        monitor?.cancel()
        monitor = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !self.stopped, self.encodingSegment == index else { return }
            self.fail(URLError(.timedOut))
        }
    }

    private func finishSegment() {
        guard let index = encodingSegment, let output = segmentOutput,
              let playlist = vodPlaylist, let interval = playlist.interval(for: index), let server else { return }
        segmentOutput = nil
        monitor?.cancel()
        let target = server.directory.appendingPathComponent(playlist.name(for: index))
        monitor = Task { [weak self] in
            do {
                try await Self.publishSegment(output, to: target, interval: interval)
                guard let self, !self.stopped, !Task.isCancelled else { return }
                self.monitor = nil
                self.encodingSegment = nil
                CarPlayPlaybackTrace.record("segment-ready \(index)")
                server.segmentReady(index)
                if !self.ready, let address = self.vodAddress {
                    self.ready = true
                    self.onReady?(address)
                }
                self.encodeNextSegment()
            } catch {
                if !Task.isCancelled { self?.fail(error) }
            }
        }
    }

    // Rewriting the segment clocks can touch several megabytes. Keep that
    // work off the main actor and only expose the file when it is complete.
    nonisolated private static func publishSegment(_ file: URL, to target: URL, interval: Range<Double>) async throws {
        try Task.checkCancellation()
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 32 * 1_024 * 1_024 else {
            throw URLError(.cannotDecodeContentData)
        }
        let data = try Data(contentsOf: file)
        let trimmed = try CarPlayVODPlaylist.removingSeekPreroll(from: data, before: interval.lowerBound,
            duration: interval.upperBound - interval.lowerBound)
        try Task.checkCancellation()
        if trimmed != data { try trimmed.write(to: file, options: .atomic) }
        try FileManager.default.moveItem(at: file, to: target)
    }

    private func beginOutput(media: VLCMedia, videoID: String, transcodesAudio: Bool,
                             server: CarPlayHLSServer, url: URL) {
        var conversion: [String] = []
        if transcodesVideo {
            conversion += ["vcodec=h264", "venc=avcodec{codec=h264_videotoolbox,keyint=30,bframes=0}",
                           "vb=4000", "fps=30", "maxwidth=1280", "maxheight=720"]
        }
        if transcodesAudio { conversion += ["acodec=mp4a", "aenc=avcodec{codec=aac}", "ab=160", "channels=2", "samplerate=48000"] }
        let transcode = conversion.isEmpty ? "" : "transcode{\(conversion.joined(separator: ","))}:"
        // Use the real demuxer ES ID, including any program prefix. Numeric
        // metadata IDs are not sufficient to map a video into the HLS master.
        let variants = "{\(videoID)}"
        media.addOption(":sout=#\(transcode)hls{variants='\(variants)',seg-type=fmp4,seg-len=1,max-seg-len=6,num-seg=16,pace=true,out-dir='\(server.directory.path)',base-url='/\(server.token)'}")
        media.addOption(":sout-all")
        media.addOption(":sout-keep")
        media.addOption(":network-caching=300")
        media.addOption(":file-caching=300")
        if startPosition > 0 { media.addOption(":start-time=\(startPosition)") }
        encoder.media = media
        encodingBegan = true
        encoder.play()
        monitor = Task { [weak self, weak server] in
            let deadline = Date().addingTimeInterval(30)
            while !Task.isCancelled {
                guard let self, let server, !self.stopped, self.server === server else { return }
                do {
                    let available = try await server.prepareSnapshot()
                    if !self.ready && available {
                        let sample = try await server.nativeVideoSample()
                        defer { try? FileManager.default.removeItem(at: sample) }
                        try await Self.validateVideo(sample)
                        try Task.checkCancellation()
                        guard !self.stopped else { return }
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace") {
                            print("[Mirivo.CarPlay] video-validated transcode=\(self.transcodesVideo)")
                        }
                        #endif
                        self.ready = true
                        self.onReady?(url)
                    }
                    if !self.ready && Date() >= deadline { throw URLError(.timedOut) }
                    try await Task.sleep(for: .milliseconds(self.ready ? 1_000 : 150))
                } catch is CancellationError { return }
                catch {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace") {
                        let failure = error as NSError
                        print("[Mirivo.CarPlay] output-failed transcode=\(self.transcodesVideo) \(failure.domain):\(failure.code)")
                    }
                    #endif
                    self.fail(error); return
                }
            }
        }
    }

    func setPaused(_ paused: Bool) {
        requestedPause = paused
        // A requested VOD segment must finish even when the consumer is paused.
        if vodPlaylist != nil { return }
        guard ready, !stopped, !producerFinished else { return }
        if paused {
            if encoder.state != .paused && !pausePending { pausePending = true; encoder.pause() }
        } else if !pausePending { encoder.play() }
    }

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in self?.encoderStateChanged(newState) }
    }

    func mediaPlayerLengthChanged(_ length: Int64) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, !self.live, self.vodPlaylist == nil, length > 0 else { return }
            self.duration = Double(length) / 1_000
        }
    }

    private func encoderStateChanged(_ newState: VLCMediaPlayerState) {
        if stopped {
            if newState == .stopped || newState == .nothingSpecial { finishStopping() }
            return
        }
        if vodPlaylist != nil {
            if newState == .error && encoder.state == .error { fail(URLError(.cannotDecodeContentData)) }
            else if newState == .stopped && encoder.state == .stopped { finishSegment() }
            return
        }
        if newState == .error && encoder.state == .error { fail(URLError(.cannotDecodeContentData)) }
        if newState == .stopped && encodingBegan && ready && encoder.state == .stopped { producerFinished = true }
        if newState == .paused {
            pausePending = false
            if !requestedPause { encoder.play() }
        }
        // EOF leaves the completed playlist and its tail available until the
        // AVPlayer consumer finishes. A producer finishing is not a playback failure.
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        pendingSegments.removeAll()
        monitor?.cancel(); monitor = nil
        onReady = nil; onFailure = nil
        probe?.stop(); probe = nil
        server?.stop()
        if encoder.state != .stopped && encoder.state != .nothingSpecial {
            stoppingRetention = self
            encoder.stop()
        } else { finishStopping() }
    }

    private func finishStopping() {
        // Stop is asynchronous in VLC. Never remove a directory that the
        // encoder can still write into during a channel switch or cancellation.
        server?.removeOutput(); server = nil
        stoppingRetention = nil
    }

    private func fail(_ error: Error) {
        guard !stopped else { return }
        let callback = onFailure
        stop()
        callback?(error)
    }

    nonisolated private static func validateVideo(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw URLError(.cannotDecodeContentData)
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { throw reader.error ?? URLError(.cannotDecodeContentData) }
        // Decode in order. Seeking into a standalone fMP4 fragment can start
        // on a dependent frame and falsely reject an otherwise valid stream.
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard CMSampleBufferGetImageBuffer(sample) != nil else { throw URLError(.cannotDecodeContentData) }
            frames += 1
            if frames >= 12 { return }
        }
        guard frames > 0, reader.status == .completed else {
            throw reader.error ?? URLError(.cannotDecodeContentData)
        }
    }

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    @MainActor
    private final class SegmentDelegate: NSObject, @preconcurrency VLCMediaPlayerDelegate {
        private let stateChanged: (VLCMediaPlayerState) -> Void
        init(stateChanged: @escaping (VLCMediaPlayerState) -> Void) { self.stateChanged = stateChanged }
        func mediaPlayerStateChanged(_ state: VLCMediaPlayerState) {
            Task { @MainActor [weak self] in self?.stateChanged(state) }
        }
    }
}
