import Foundation
@preconcurrency import GoogleCast

/// The receiver owns decoding; connection and media errors stay recoverable.
@MainActor
final class CastPlayback: NSObject, @preconcurrency GCKSessionManagerListener,
                          @preconcurrency GCKRemoteMediaClientListener, @preconcurrency GCKRequestDelegate {
    var onState: ((PlaybackController.State) -> Void)?
    var onTime: ((Double, Double, Bool, Bool) -> Void)?
    var onFinished: (() -> Void)?
    private let manager = CastServices.context.sessionManager
    private var client: GCKRemoteMediaClient?
    private var device: GCKDevice?
    private var load: GCKMediaLoadRequestData?
    private var contentID: String?
    private var active = false
    private var loaded = false
    private var loadRequestID: GCKRequestID?
    private var loadCompleted = false
    private var mediaSessionID: Int?
    private var requests: [GCKRequestID: GCKRequest] = [:]
    private var seekCompletions: [GCKRequestID: () -> Void] = [:]
    private var timer: Timer?

    func open(url: URL, device: GCKDevice, title: String?, live: Bool, startAt: Double, paused: Bool) {
        self.device = device
        active = true
        contentID = url.absoluteString
        let media = GCKMediaInformationBuilder(contentURL: url)
        media.contentID = url.absoluteString
        media.contentType = Self.contentType(for: url)
        media.streamType = live ? .live : .buffered
        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(title ?? L10n.tr("iPhone ekranı"), forKey: kGCKMetadataKeyTitle)
        media.metadata = metadata
        let request = GCKMediaLoadRequestDataBuilder()
        request.mediaInformation = media.build()
        request.autoplay = NSNumber(value: !paused)
        request.startTime = live ? 0 : max(0, startAt)
        load = request.build()
        manager.add(self)
        onState?(.loading)
        if let session = manager.currentCastSession, session.device.isSameDevice(as: device), session.connectionState == .connected {
            loadMedia(session)
        } else if !manager.startSession(with: device) { onState?(.failed) }
        guard active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishStatus() }
        }
    }

    func stop() {
        active = false
        timer?.invalidate(); timer = nil
        requests.values.forEach { $0.delegate = nil }; requests.removeAll()
        let completions = Array(seekCompletions.values)
        seekCompletions.removeAll()
        client?.remove(self)
        // Another sender may have replaced our media. Never stop its new item.
        if let status = client?.mediaStatus, status.mediaInformation?.contentID == contentID,
           mediaSessionID == nil || mediaSessionID == status.mediaSessionID { client?.stop() }
        client = nil
        load = nil; loaded = false; loadCompleted = false; loadRequestID = nil; mediaSessionID = nil
        manager.remove(self)
        completions.forEach { $0() }
    }
    static func disconnect() { CastServices.context.sessionManager.endSessionAndStopCasting(true) }
    func play() { if let request = client?.play() { track(request) } }
    func pause() { if let request = client?.pause() { track(request) } }
    func seek(to time: Double, completion: @escaping () -> Void) {
        guard let client else { completion(); return }
        let options = GCKMediaSeekOptions()
        options.interval = time
        let request = client.seek(with: options)
        seekCompletions[request.requestID] = completion
        track(request)
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/x-mpegURL"
        case "ts", "mpegts": return "video/mp2t"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "aif", "aiff": return "audio/aiff"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "mov": return "video/quicktime"
        default: return "video/mp4"
        }
    }

    private func track(_ request: GCKRequest) { requests[request.requestID] = request; request.delegate = self }
    private func loadMedia(_ session: GCKCastSession) {
        guard active, let device, session.device.isSameDevice(as: device), let load,
              let client = session.remoteMediaClient else { return }
        self.load = nil
        self.client = client
        client.add(self)
        let request = client.loadMedia(with: load)
        loadRequestID = request.requestID
        track(request)
    }
    private func publishStatus() {
        guard active, loadCompleted, let client, let status = client.mediaStatus else { return }
        guard status.mediaInformation?.contentID == contentID,
              mediaSessionID == nil || mediaSessionID == status.mediaSessionID else {
            if loaded { onFinished?() }
            return
        }
        mediaSessionID = status.mediaSessionID
        let duration = status.mediaInformation?.streamDuration ?? 0
        onTime?(client.approximateStreamPosition(), duration,
                status.isMediaCommandSupported(kGCKMediaCommandSeek), status.mediaInformation?.streamType == .live)
        switch status.playerState {
        case .playing: loaded = true; onState?(.playing)
        case .paused: loaded = true; onState?(.paused)
        case .buffering, .loading: onState?(.loading)
        case .idle:
            if status.idleReason == .error { onState?(.failed) }
            else if loaded { onFinished?() }
        default: break
        }
    }
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        guard self.client === client else { return }; publishStatus()
    }
    func requestDidComplete(_ request: GCKRequest) {
        guard requests.removeValue(forKey: request.requestID) != nil else { return }
        if request.requestID == loadRequestID { loadCompleted = true; loadRequestID = nil }
        seekCompletions.removeValue(forKey: request.requestID)?()
        publishStatus()
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        guard active, requests.removeValue(forKey: request.requestID) != nil else { return }
        seekCompletions.removeValue(forKey: request.requestID)?()
        onState?(.failed)
    }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
        guard active, requests.removeValue(forKey: request.requestID) != nil else { return }
        seekCompletions.removeValue(forKey: request.requestID)?()
        if request.requestID == loadRequestID { onState?(.failed) }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        if let session = session as? GCKCastSession { loadMedia(session) }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        guard active, let device, session.device.isSameDevice(as: device) else { return }
        if let session = session as? GCKCastSession {
            if load != nil { loadMedia(session) }
            else { client?.remove(self); client = session.remoteMediaClient; client?.add(self); publishStatus() }
        }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        guard active, let device, session.device.isSameDevice(as: device) else { return }
        onState?(.failed)
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        guard active, let device, session.device.isSameDevice(as: device) else { return }
        if error != nil { onState?(.failed) } else { onFinished?() }
    }
}
