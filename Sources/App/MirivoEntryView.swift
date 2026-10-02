import SwiftUI

/// The home screen is ready immediately; the brief brand transition never intercepts input.
struct MirivoEntryView: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        MirivoRootView(model: model)
            .overlay {
                if !entered && !reduceMotion {
                    ZStack {
                        MirrorStyle.background.ignoresSafeArea()
                        VStack(spacing: 20) {
                            MirrorMark().frame(width: 64, height: 64)
                            Text(BrandIdentity.name)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .task {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { entered = true }
            }
    }
}
