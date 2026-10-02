import SwiftUI

@main
struct CarMirrorApp: App {
    @StateObject private var model = MirrorModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MirrorHomeView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.foregrounded() }
                }
        }
    }
}
