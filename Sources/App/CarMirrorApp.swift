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
                    if !startedPiPProbe, let index = arguments.firstIndex(of: "-mirivo-pip-probe"),
                       arguments.indices.contains(index + 1), ["mp4", "mkv", "hls"].contains(arguments[index + 1]) {
                        startedPiPProbe = true
                        let kind = arguments[index + 1]
                        let url = kind == "hls"
                            ? ProcessInfo.processInfo.environment["MIRIVO_PIP_QA_LIVE_URL"].flatMap { try? MediaURL.validate($0) }
                            : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("MirivoPiPProbe/options." + kind)
                        if let url, (!url.isFileURL || FileManager.default.fileExists(atPath: url.path)),
                           model.playMedia(MediaChannel(title: "PiP QA", url: url)) { model.presentingPlayer = true }
                    }
                    #endif
                    await updates.refresh()
                    await NotificationStore.shared.refresh()
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
                        }
                    }
                }
        }
    }
}
