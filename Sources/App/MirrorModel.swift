import Foundation
import Combine
import CarPlay

@MainActor
final class MirrorModel: ObservableObject {
    static let shared = MirrorModel()
    @Published private(set) var capture: CaptureStatus?
    @Published private(set) var carPlayConnected = false
    @Published private(set) var supportsVideo: Bool?
    @Published var errorMessage: String?
    @Published var showingPreview = false
    @Published private(set) var storageReady = false
    let playback = PlaybackController()
    let carPlayBuild = Bundle.main.object(forInfoDictionaryKey: "CMCarPlayEnabled") as? String == "YES"
    private var store: BroadcastSessionStore?
    private var timer: Timer?
    private var playbackSessionID: UUID?

    private init() {
        do { store = try BroadcastSessionStore(); storageReady = true }
        catch { errorMessage = error.localizedDescription }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var readyToPlay: Bool { capture?.canPlay() == true }
    var broadcasting: Bool {
        guard let capture else { return false }
        return capture.isFresh() && [.preparing, .live].contains(capture.phase)
    }

    var captureTitle: String {
        guard let capture else { return "Paylaşıma hazır" }
        if [.live, .preparing].contains(capture.phase), !capture.isFresh() { return "Yayın bağlantısı kesildi" }
        switch capture.phase {
        case .preparing: return "Yayın hazırlanıyor"
        case .live: return "Ekran yayını açık"
        case .paused: return "Yayın duraklatıldı"
        case .stopped: return "Paylaşım durduruldu"
        case .failed: return "Yayın başlatılamadı"
        }
    }

    var carTitle: String {
        if !carPlayBuild { return "iPhone test sürümü" }
        if !carPlayConnected { return "CarPlay bağlantısı bekleniyor" }
        if supportsVideo == true { return "Araç video desteği bildirdi" }
        if supportsVideo == false { return "Araç resmî video desteği bildirmedi" }
        return "Bu iOS sürümünde video desteği sorgulanamıyor"
    }

    func refresh() {
        capture = store?.readStatus()
        if let playbackSessionID,
           capture?.sessionID != playbackSessionID || !readyToPlay {
            stopPlayback()
        }
    }

    func connected(supportsVideo: Bool?) {
        carPlayConnected = true
        self.supportsVideo = supportsVideo
        refresh()
    }

    func disconnected() {
        carPlayConnected = false
        supportsVideo = nil
        if playback.destination == .carPlay { stopBroadcast() }
    }

    func startPreview() {
        guard let capture, capture.canPlay(), let url = capture.loopbackURL else { return }
        do {
            try playback.play(url: url, destination: .preview)
            playbackSessionID = capture.sessionID
            showingPreview = true
        } catch { errorMessage = error.localizedDescription }
    }

    func playInCar() {
        guard carPlayConnected, supportsVideo == true else {
            errorMessage = "Bu bağlantı Apple’ın CarPlay Video desteğini bildirmiyor."
            return
        }
        guard let capture, capture.canPlay() else {
            errorMessage = "Önce iPhone’da ekran yayınını başlat."
            return
        }
        // A receiver cannot fetch 127.0.0.1 on the phone. Do not silently substitute it.
        guard let url = capture.networkURL else {
            errorMessage = "Araç oynatımı için erişilebilir bir yerel ağ adresi bulunamadı. Wi-Fi bağlantısını kontrol et."
            return
        }
        do {
            try playback.play(url: url, destination: .carPlay)
            playbackSessionID = capture.sessionID
        } catch { errorMessage = error.localizedDescription }
    }

    func stopPlayback() {
        playback.stop()
        playbackSessionID = nil
        showingPreview = false
    }

    func stopBroadcast() {
        stopPlayback()
        guard let capture, capture.isFresh() else { return }
        do { try store?.requestStop(sessionID: capture.sessionID) }
        catch { errorMessage = error.localizedDescription }
    }
}
