import SwiftUI

@main
struct CarMirrorApp: App {
    @StateObject private var model = MirrorModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") {
            try? SourceLibrary.shared.clear()
            SharedPreferences.defaults.removeObject(forKey: "language")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MirivoEntryView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.foregrounded() }
                }
        }
    }
}
