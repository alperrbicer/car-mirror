import SwiftUI

@main
struct CarMirrorApp: App {
    @UIApplicationDelegateAdaptor(MirivoAppDelegate.self) private var appDelegate
    @StateObject private var model = MirrorModel.shared
    @StateObject private var updates = AppUpdateStore.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var startedPiPProbe = false
    #endif

    init() {
        FirebaseServices.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") {
            if !ProcessInfo.processInfo.arguments.contains("-mirivo-ui-preserve-library") {
                try? SourceLibrary.shared.clear()
                if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-continue-watching") {
                    seedContinuationTestData()
                }
                if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-artwork-history") {
                    seedArtworkContinuationTestData()
                }
            }
            SharedPreferences.defaults.removeObject(forKey: "language")
        }
        #endif
    }

    #if DEBUG
    private func seedContinuationTestData() {
        let library = SourceLibrary.shared
        try? library.add(name: "Mirivo Demo", kind: .playlist,
                         secret: SourceSecret(url: URL(string: "http://127.0.0.1:8769/demo.m3u")!),
                         access: ProductAccess(salesEnabled: false, verifiedPro: false))
        guard let source = library.sources.last else { return }
        for (index, title) in ["Kıyı Hikâyeleri S01-E02", "Uzun Yol", "Gece Vardiyası S02-E04", "Sessiz Şehir", "Bir Başka Gün S01-E07"].enumerated() {
            let channel = MediaChannel(title: title, url: URL(string: "http://127.0.0.1:8769/tracks/options.mp4?item=\(index)")!)
            try? LastPlaybackStore.shared.save(LastPlaybackRecord(channel: channel, sourceID: source.id,
                position: Double(30 + index * 3), duration: 90, isLive: false))
        }
    }
    private func seedArtworkContinuationTestData() {
        let library = SourceLibrary.shared
        try? library.add(name: "Görsel Kitaplık", kind: .playlist,
                         secret: SourceSecret(url: URL(string: "http://127.0.0.1:8774/catalog/get.php?username=artwork&password=fixture&type=m3u_plus")!),
                         access: ProductAccess(salesEnabled: false, verifiedPro: false))
        guard let source = library.sources.last else { return }
        let entries = [("Eksik Görsel", "Diğer", "movie", 104), ("Yolun Ötesi", "FİLM: Macera", "movie", 102),
                       ("Gece Vardiyası S02-E04", "DİZİ: Exxen", "series", 304), ("Mavi Yolculuk", "FİLM: Macera", "movie", 101),
                       ("Kıyı Hikâyeleri S01-E02", "DİZİ: Exxen", "series", 202)]
        for (index, item) in entries.enumerated() {
            // Deliberately omit metadata to exercise artwork lookup for older history.
            let channel = MediaChannel(title: item.0, group: item.1,
                                       url: URL(string: "http://127.0.0.1:8774/\(item.2)/artwork/fixture/\(item.3).mp4")!)
            try? LastPlaybackStore.shared.save(LastPlaybackRecord(channel: channel, sourceID: source.id,
                position: Double(30 + index * 3), duration: 90, isLive: false))
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = updates.requiredURL {
                    RequiredUpdateView(updates: updates, url: url)
                } else {
                    MirivoEntryView(model: model)
                }
            }
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    // Device-only QA uses local fixtures or an explicitly supplied
                    // live test feed without changing the user's library.
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("-mirivo-ui-testing"), arguments.contains("-mirivo-ui-carplay") {
                        model.connected(supportsVideo: !arguments.contains("-mirivo-ui-carplay-no-video"))
                    }
                    if arguments.contains("-mirivo-ui-testing") {
                        if arguments.contains("-mirivo-ui-carplay-display") {
                            model.externalScreenConnected(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                role: .carPlay, size: CGSize(width: 800, height: 480))
                        }
                        if arguments.contains("-mirivo-ui-external-display") {
                            model.externalScreenConnected(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                role: .externalNonInteractive, size: CGSize(width: 1920, height: 1080))
                        }
                    }
                    if !startedPiPProbe, let index = arguments.firstIndex(of: "-mirivo-pip-probe"),
                       arguments.indices.contains(index + 1), ["mp4", "mkv", "hls"].contains(arguments[index + 1]) {
                        startedPiPProbe = true
                        let kind = arguments[index + 1]
                        let url = kind == "hls"
                            ? ProcessInfo.processInfo.environment["MIRIVO_PIP_QA_LIVE_URL"].flatMap { try? MediaURL.validate($0) }
                            : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("MirivoPiPProbe/options." + kind)
                        if let url, (!url.isFileURL || FileManager.default.fileExists(atPath: url.path)),
                           model.playMedia(MediaChannel(title: "PiP QA", url: url)) {
                            model.presentingPlayer = true
                            if arguments.contains("-mirivo-pip-selftest") {
                                Task { await model.playback.runPictureInPictureProbe() }
                            }
                        }
                    }
                    #endif
                    await updates.refresh()
                    await NotificationStore.shared.refresh()
                    await CarConnectionReminderStore.shared.refreshAuthorization()
                }
                .onChange(of: updates.requiredURL) { _, url in
                    if url != nil { model.stopBroadcast(); model.stopProbe(); model.stopPlayback() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.foregrounded()
                        Task {
                            await updates.refresh()
                            await NotificationStore.shared.refresh()
                            await CarConnectionReminderStore.shared.refreshAuthorization()
                        }
                    } else if phase == .background, model.playback.tvDevice != nil {
                        // Send an explicit Cast session stop before iOS can
                        // suspend or terminate the sender. Stopping only the
                        // local playback controller can leave the receiver
                        // playing independently.
                        model.stopPlayback()
                        model.disconnectTV()
                    }
                }
        }
    }
}
