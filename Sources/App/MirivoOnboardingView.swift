import SwiftUI

struct MirivoOnboardingView: View {
    let onFinish: (_ showPro: Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var step = 0
    @State private var finishing = false
    @AccessibilityFocusState private var focusedStep: Int?

    private let pageCount = 3
    private var pageOrder: [Int] { layoutDirection == .rightToLeft ? [2, 1, 0] : [0, 1, 2] }

    private func title(for index: Int) -> String {
        switch index {
        case 0: L10n.tr("Kaynakların, her ekranda.")
        case 1: L10n.tr("İndir, sonra izle.")
        default: L10n.tr("Sevdiğin her şey, bir arada.")
        }
    }
    private func detail(for index: Int) -> String {
        switch index {
        case 0: L10n.tr("Ekranını, videolarını ve fotoğraflarını paylaş. Google Cast, AirPlay veya uyumlu araçlarda CarPlay ile büyük ekranda izle.")
        case 1: L10n.tr("Uygun film ve bölümleri indir, internet olmadan izle.")
        default: L10n.tr("Oynatma listelerini ve IPTV kaynaklarını ekle. Film, dizi ve canlı yayınlarını tek yerde bul.")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                ForEach(pageOrder, id: \.self) { index in
                    page(index)
                        .environment(\.layoutDirection, layoutDirection)
                        .tag(index)
                        .accessibilityHidden(index != step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Reverse the page order for RTL, while preserving native swipe behavior.
            .environment(\.layoutDirection, .leftToRight)
            .allowsHitTesting(!finishing)
            .accessibilityIdentifier("onboarding-pager")
        }
        .foregroundStyle(.white)
        .background(MirrorStyle.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .onChange(of: step) { _, index in focusedStep = index }
        .sensoryFeedback(.selection, trigger: step)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                MirrorMark().frame(width: 30, height: 30)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(BrandIdentity.name).font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(BrandIdentity.name)
            Spacer(minLength: 16)
            Button(L10n.tr("Atla")) { finishIntroduction() }
                .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.secondary)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                .buttonStyle(.plain).disabled(finishing).accessibilityIdentifier("onboarding-skip")
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    private func page(_ index: Int) -> some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 560
            let short = geometry.size.height < 500
            ScrollView {
                VStack(spacing: short ? 18 : compact ? 22 : 30) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        OnboardingArtwork(step: index)
                            .frame(height: min(280, max(140, geometry.size.height * (short ? 0.34 : 0.43))))
                    }
                    VStack(spacing: 14) {
                        Text(title(for: index))
                            .font(.system(short ? .title : .largeTitle, design: .default, weight: .bold))
                            .tracking(L10n.appLanguage.allowsLetterSpacing ? -0.9 : 0)
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($focusedStep, equals: index)
                            .accessibilityIdentifier("onboarding-title-\(index)")
                        Text(detail(for: index))
                            .font(short ? .callout : .body).foregroundStyle(Color.white.opacity(0.68)).lineSpacing(3)
                    }
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    supportingDetails(for: index).frame(maxWidth: 420)
                }
                .padding(.horizontal, 28).padding(.vertical, short ? 12 : compact ? 16 : 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func supportingDetails(for index: Int) -> some View {
        VStack(spacing: 18) {
            switch index {
            case 0:
                feature(L10n.tr("Ekranını paylaş"), symbol: "rectangle.on.rectangle")
                note(L10n.tr("CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir."))
            case 2:
                feature(L10n.tr("Dizilerini sezon ve bölümleriyle keşfet."), symbol: "square.stack")
                note(L10n.tr("Mirivo içerik sağlamaz. Kendi kaynağını ekleyerek başlayabilirsin."))
            default:
                if dynamicTypeSize >= .xxxLarge {
                    VStack(alignment: .leading, spacing: 16) { viewingFeatures }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { viewingFeatures }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 14) { viewingFeatures }
                    }
                }
            }
        }
    }

    private var viewingFeatures: some View {
        Group {
            feature(L10n.tr("İzlemeye devam et"), symbol: "play.circle")
            feature(L10n.tr("Resim İçinde Resim"), symbol: "pip")
        }
    }

    private func feature(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).foregroundStyle(Color.white.opacity(0.84))
        } icon: {
            Image(systemName: symbol).foregroundStyle(MirrorStyle.accent)
        }
        .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(MirrorStyle.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            OnboardingPageControl(currentPage: step, numberOfPages: pageCount,
                                  pageTitle: title(for: step), onChange: changeStep)
                .frame(width: 120, height: 44).frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button { changeStep(to: step - 1) } label: {
                        Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                            .foregroundStyle(MirrorStyle.secondary)
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(L10n.tr("Geri"))
                    .accessibilityIdentifier("onboarding-back")
                    .disabled(step == 0 || finishing).opacity(step == 0 ? 0 : 1)
                    .accessibilityHidden(step == 0)
                }
            Button {
                if step < pageCount - 1 { changeStep(to: step + 1) }
                else { finishIntroduction() }
            } label: {
                HStack(spacing: 10) {
                    Text(L10n.tr(step == pageCount - 1 ? "Başlayalım" : "Devam et"))
                    if finishing { ProgressView().tint(MirrorStyle.background) }
                    else { Image(systemName: "arrow.forward").font(.body.weight(.semibold)) }
                }
            }
            .buttonStyle(MirivoButtonStyle(prominent: true)).accessibilityIdentifier("onboarding-next")
        }
        .disabled(finishing)
        .padding(.horizontal, 24).padding(.bottom, 12).padding(.top, 4)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background {
            MirrorStyle.background.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [MirrorStyle.background.opacity(0), MirrorStyle.background],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 20).offset(y: -20)
                }
                .allowsHitTesting(false)
        }
    }

    private func changeStep(to next: Int) {
        guard !finishing, (0..<pageCount).contains(next) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { step = next }
    }

    private func finishIntroduction() {
        guard !finishing else { return }
        finishing = true
        Task {
            await purchases.refresh()
            onFinish(purchases.salesEnabled && !purchases.verifiedPro)
            finishing = false
        }
    }
}

/// UIKit supplies tap/scrub behavior and VoiceOver's adjustable page control.
private struct OnboardingPageControl: UIViewRepresentable {
    let currentPage: Int
    let numberOfPages: Int
    let pageTitle: String
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.22)
        control.currentPageIndicatorTintColor = UIColor(MirrorStyle.accent)
        control.backgroundStyle = .minimal
        control.accessibilityIdentifier = "onboarding-pages"
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.onChange = onChange
        control.numberOfPages = numberOfPages
        control.currentPage = currentPage
        control.isEnabled = context.environment.isEnabled
        control.accessibilityLabel = pageTitle
        control.semanticContentAttribute = context.environment.layoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
    }
    final class Coordinator: NSObject {
        var onChange: (Int) -> Void
        init(onChange: @escaping (Int) -> Void) { self.onChange = onChange }
        @objc func changed(_ control: UIPageControl) { onChange(control.currentPage) }
    }
}

/// Original vector scenes suggest a personal library without bundling provider content.
private struct OnboardingArtwork: View {
    let step: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse().fill(MirrorStyle.accent.opacity(0.10))
                    .frame(width: 270, height: 170).blur(radius: 38)
                switch step {
                case 0: screens
                case 1: offlineDownloads
                default: library
                }
            }
            .frame(width: 340, height: 270)
            .scaleEffect(min(geometry.size.width / 340, geometry.size.height / 270))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .dynamicTypeSize(.medium).accessibilityHidden(true).allowsHitTesting(false)
    }

    private var library: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(MirrorStyle.accent.opacity(0.06))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(MirrorStyle.accent.opacity(0.10)) }
                .frame(width: 254, height: 202).rotationEffect(.degrees(-7)).offset(x: -8, y: -14)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.tr("Kaynaklar")).font(.system(size: 18, weight: .bold))
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MirrorStyle.accent).frame(width: 26, height: 26)
                        .background(MirrorStyle.accent.opacity(0.12), in: Circle())
                }
                HStack(spacing: 10) {
                    poster(0, symbol: "film")
                    poster(1, symbol: "rectangle.stack")
                    poster(2, symbol: "dot.radiowaves.left.and.right")
                }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MirrorStyle.accent)
                    Text("M3U · IPTV").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Image(systemName: "square.grid.2x2").foregroundStyle(.white.opacity(0.4))
                }.font(.system(size: 12))
            }
            .padding(18).frame(width: 284).background(panel)
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.35), radius: 20, y: 14).rotationEffect(.degrees(2))
        }
    }

    private func poster(_ palette: Int, symbol: String) -> some View {
        OnboardingLandscape(palette: palette)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9)).padding(9)
            }
            .frame(height: 122).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)) }
    }

    private var offlineDownloads: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(MirrorStyle.accent)
                    Text(L10n.tr("İndirilenler")).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                OnboardingLandscape(palette: 0)
                    .overlay {
                        Image(systemName: "play.fill").font(.system(size: 18, weight: .semibold)).offset(x: 1)
                            .frame(width: 46, height: 46).background(.black.opacity(0.25), in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.28)) }
                    }
                    .frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 14))
                HStack {
                    Text(SeriesText.season(1) + " · " + SeriesText.episode(3))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MirrorStyle.accent)
                }
            }
            .padding(16).frame(width: 284).background(panel)
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.35), radius: 20, y: 14).offset(x: -9, y: -20)
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash").font(.system(size: 23)).foregroundStyle(MirrorStyle.accent)
                Text(L10n.tr("Çevrimdışı izlemeye hazır")).font(.system(size: 11, weight: .medium))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 13).frame(width: 218, alignment: .leading)
            .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.15)) }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6).offset(x: 45, y: 112)
        }
    }

    private var screens: some View {
        VStack(spacing: 24) {
            ScreenLinkIllustration(active: true)
            HStack(spacing: 7) {
                route("Google Cast", symbol: "tv")
                route("AirPlay", symbol: "airplay.video")
                route("CarPlay", symbol: "car.side")
            }
        }
    }
    private func route(_ name: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(MirrorStyle.accent)
            Text(name).foregroundStyle(.white.opacity(0.8))
        }
        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 8)
        .background(MirrorStyle.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(MirrorStyle.hairline) }
    }
    private var panel: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.17, blue: 0.18), MirrorStyle.surface],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private struct OnboardingLandscape: View {
    let palette: Int
    private var sky: Color {
        switch palette {
        case 1: Color(red: 0.16, green: 0.20, blue: 0.39)
        case 2: Color(red: 0.58, green: 0.31, blue: 0.24)
        default: Color(red: 0.09, green: 0.36, blue: 0.39)
        }
    }
    private var light: Color {
        switch palette {
        case 1: Color(red: 0.69, green: 0.72, blue: 0.95)
        case 2: Color(red: 0.99, green: 0.78, blue: 0.52)
        default: Color(red: 0.69, green: 0.94, blue: 0.81)
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: [sky, sky.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                Circle().fill(light.opacity(0.14)).frame(width: height * 0.72, height: height * 0.72)
                    .position(x: width * 0.7, y: height * 0.29)
                Circle().fill(light).frame(width: height * 0.25, height: height * 0.25)
                    .position(x: width * 0.7, y: height * 0.29)
                ridge(width: width, height: height, crest: 0.36).fill(light.opacity(0.25))
                ridge(width: width, height: height, crest: 0.6)
                    .fill(LinearGradient(colors: [sky, Color(red: 0.025, green: 0.10, blue: 0.12)],
                                         startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: -1, y: 1)
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .center, endPoint: .bottom)
            }
        }.clipped()
    }
    private func ridge(width: CGFloat, height: CGFloat, crest: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height * 0.8))
            path.addCurve(to: CGPoint(x: width, y: height * 0.68),
                          control1: CGPoint(x: width * 0.35, y: height * (crest - 0.3)),
                          control2: CGPoint(x: width * 0.5, y: height * crest))
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
    }
}
