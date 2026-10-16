import SwiftUI

struct MirivoOnboardingView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var step = 0
    @State private var showingPro = false
    @State private var finishing = false
    @AccessibilityFocusState private var headingFocused: Bool

    private var title: String {
        switch step {
        case 0: L10n.tr("Sevdiğin her şey, bir arada.")
        case 1: L10n.tr("İzlemeye devam et")
        default: L10n.tr("Büyük ekranda daha fazlası.")
        }
    }
    private var detail: String {
        switch step {
        case 0: L10n.tr("Oynatma listelerini ve IPTV kaynaklarını ekle. Film, dizi ve canlı yayınlarını tek yerde bul.")
        case 1: L10n.tr("Bir bölüme başla, ara ver, kaldığın yerden sürdür. Mirivo izleme ilerlemeni hatırlar.")
        default: L10n.tr("İçeriklerini uyumlu bir TV’ye aktar veya ekranını paylaş.")
        }
    }
    private var section: String {
        L10n.tr(step == 0 ? "Kaynaklar" : step == 1 ? "İzlemeye devam et" : "Ekranını paylaş")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MirrorMark().frame(width: 32, height: 32)
                Text(BrandIdentity.name).font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(L10n.tr("Atla")) { finishIntroduction() }
                    .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(finishing).accessibilityIdentifier("onboarding-skip")
            }
            .padding(.horizontal, 24).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    OnboardingArtwork(step: step)
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 190 : 260)
                        .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 18) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(section)
                                .font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(MirrorStyle.accent.opacity(0.09), in: Capsule())
                        }
                        Text(title)
                            .font(.system(.largeTitle, design: .default, weight: .bold))
                            .tracking(L10n.appLanguage.allowsLetterSpacing ? -0.8 : 0)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                            .accessibilityIdentifier("onboarding-title-\(step)")
                        Text(detail)
                            .font(.body).foregroundStyle(MirrorStyle.secondary).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                        if step == 0 {
                            Text(L10n.tr("Mirivo içerik sağlamaz. Kendi kaynağını ekleyerek başlayabilirsin."))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 24)
                .frame(maxWidth: 540).frame(maxWidth: .infinity)
                .id(step)
                .transition(.opacity)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .topTrailing) {
                MirrorStyle.background
                RadialGradient(colors: [MirrorStyle.accent.opacity(0.09), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 420)
            }.ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .fullScreenCover(isPresented: $showingPro, onDismiss: onFinish) {
            NavigationStack { ProView(allowsFreeContinuation: true) }
                .environment(\.locale, Locale(identifier: L10n.language))
                .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        .onChange(of: step) { _, _ in headingFocused = true }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack {
                Button { changeStep(to: step - 1) } label: {
                    Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.tr("Geri"))
                .accessibilityIdentifier("onboarding-back")
                .disabled(step == 0 || finishing).opacity(step == 0 ? 0 : 1)
                .accessibilityHidden(step == 0)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == step ? MirrorStyle.accent : .white.opacity(0.16))
                            .frame(width: index == step ? 26 : 7, height: 7)
                    }
                }.accessibilityHidden(true)
                Spacer()
                Text("\(step + 1) / 3").font(.caption.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                    .fixedSize(horizontal: true, vertical: false).frame(minWidth: 44, minHeight: 44)
            }
            Button {
                if step < 2 { changeStep(to: step + 1) }
                else { finishIntroduction() }
            } label: {
                HStack(spacing: 10) {
                    Text(L10n.tr(step == 2 ? "Başlayalım" : "Devam et"))
                    if finishing { ProgressView().tint(MirrorStyle.background) }
                    else { Image(systemName: "arrow.forward").font(.body.weight(.semibold)) }
                }
            }
            .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(finishing)
            .accessibilityIdentifier("onboarding-next")
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
        .frame(maxWidth: 540).frame(maxWidth: .infinity)
        .background(MirrorStyle.background)
    }

    private func changeStep(to next: Int) {
        guard (0..<3).contains(next) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = next }
    }

    private func finishIntroduction() {
        guard !finishing else { return }
        finishing = true
        Task {
            await purchases.refresh()
            if purchases.verifiedPro || !purchases.salesEnabled { onFinish() }
            else { showingPro = true }
            finishing = false
        }
    }
}

/// Decorative artwork stays vector based and contains no bundled provider content.
private struct OnboardingArtwork: View {
    let step: Int
    private let blue = Color(red: 0.25, green: 0.42, blue: 0.58)
    private let copper = Color(red: 0.64, green: 0.37, blue: 0.25)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse().fill(MirrorStyle.accent.opacity(0.13))
                    .frame(width: 250, height: 150).blur(radius: 40)
                if step == 0 { library }
                else if step == 1 { continuation }
                else { ScreenLinkIllustration(active: true).frame(width: 320) }
            }
            .frame(width: 330, height: 240)
            .scaleEffect(min(geometry.size.width / 330, geometry.size.height / 240))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }.dynamicTypeSize(.medium).accessibilityHidden(true)
    }

    private var library: some View {
        ZStack {
            poster(symbol: "sun.horizon.fill", color: copper)
                .rotationEffect(.degrees(-15)).offset(x: -87, y: 8)
            poster(symbol: "moon.stars.fill", color: blue)
                .rotationEffect(.degrees(14)).offset(x: 87, y: 8)
            poster(symbol: "mountain.2.fill", color: MirrorStyle.accent)
                .offset(y: -8)
            Image(systemName: "play.fill").font(.title2)
                .foregroundStyle(MirrorStyle.background).frame(width: 58, height: 58)
                .background(MirrorStyle.accent, in: Circle()).offset(y: -8)
            HStack(spacing: 12) {
                ForEach(["film", "tv", "play.rectangle"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 36, height: 32)
                }
            }
            .foregroundStyle(MirrorStyle.accent).padding(9)
            .background(MirrorStyle.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
            .offset(y: 92)
        }
    }

    private func poster(symbol: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(LinearGradient(colors: [color.opacity(0.65), MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Capsule().fill(.white.opacity(0.5)).frame(width: 58, height: 4)
                    Capsule().fill(.white.opacity(0.2)).frame(width: 35, height: 3)
                }.padding(18)
            }
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.16)) }
            .frame(width: 114, height: 170)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 12)
    }

    private var continuation: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(colors: [blue.opacity(0.7), MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: "mountain.2.fill").font(.system(size: 95))
                        .foregroundStyle(.white.opacity(0.12)).offset(x: 32, y: 6)
                }
                .overlay {
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(.white.opacity(0.12), in: Circle())
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 0) {
                        Capsule().fill(MirrorStyle.accent).frame(width: 150)
                        Capsule().fill(.white.opacity(0.15))
                    }.frame(height: 4).padding(22)
                }
                .overlay { RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.15)) }
                .frame(width: 280, height: 174).rotationEffect(.degrees(-4))
            Image(systemName: "arrow.counterclockwise").font(.system(size: 28, weight: .medium))
                .foregroundStyle(MirrorStyle.accent).frame(width: 72, height: 72)
                .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 23))
                .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.13)) }
                .rotationEffect(.degrees(8)).offset(x: 110, y: 68)
        }
    }
}
