import SwiftUI

/// First launch introduces the library before offering an optional Pro upgrade.
struct MirivoEntryView: View {
    @ObservedObject var model: MirrorModel
    @AppStorage("mirivo.onboarding.completed") private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var showingIntroductionPro = false

    var body: some View {
        ZStack {
            if showingIntroductionPro {
                NavigationStack {
                    ProView(allowsBrowsing: true, onClose: { showingIntroductionPro = false })
                }
                .environment(\.locale, Locale(identifier: L10n.language))
                .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
            } else if onboardingCompleted {
                home
            } else {
                MirivoOnboardingView { showPro in
                    showingIntroductionPro = showPro
                    onboardingCompleted = true
                }
                .environment(\.locale, Locale(identifier: L10n.language))
                .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showingIntroductionPro)
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
