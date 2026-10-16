import SwiftUI

/// First launch introduces the library before offering an optional Pro upgrade.
struct MirivoEntryView: View {
    @ObservedObject var model: MirrorModel
    @AppStorage("mirivo.onboarding.completed") private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        Group {
            if onboardingCompleted {
                home
            } else {
                MirivoOnboardingView { onboardingCompleted = true }
                    .environment(\.locale, Locale(identifier: L10n.language))
                    .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
    }

    private var home: some View {
        MirivoRootView(model: model) { onboardingCompleted = false }
            .overlay {
                if !entered && !reduceMotion {
                    ZStack {
                        MirrorStyle.background.ignoresSafeArea()
                        VStack(spacing: 20) {
                            MirrorMark().frame(width: 64, height: 64)
                            Text(BrandIdentity.name)
                                .font(.system(size: 32, weight: .semibold, design: .default))
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
