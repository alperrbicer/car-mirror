import SwiftUI

@main
struct CarMirrorApp: App {
    @UIApplicationDelegateAdaptor(MirivoAppDelegate.self) private var appDelegate
    @StateObject private var model = MirrorModel.shared
    @StateObject private var updates = AppUpdateStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseServices.configure()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") {
            try? SourceLibrary.shared.clear()
            SharedPreferences.defaults.removeObject(forKey: "language")
        }
        #endif
    }

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
                    await updates.refresh()
                    await NotificationStore.shared.refresh()
                }
                .onChange(of: updates.requiredURL) { _, url in
                    if url != nil { model.stopBroadcast(); model.stopProbe(); model.stopPlayback() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.foregrounded()
                        Task { await updates.refresh(); await NotificationStore.shared.refresh() }
                    }
                }
        }
    }
}
