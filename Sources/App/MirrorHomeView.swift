import SwiftUI

struct MirrorHomeView: View {
    @ObservedObject var model: MirrorModel
    @State private var showingSettings = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var inlineActions: Bool { dynamicTypeSize.isAccessibilitySize && verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if inlineActions { actions }
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize {
                        ScreenLinkIllustration(active: model.sessionState == .presenting)
                    }
                    status
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !inlineActions {
                VStack(spacing: 14) {
                    actions
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(BrandIdentity.tagline)
                            .font(.footnote)
                            .foregroundStyle(MirrorStyle.secondary)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(MirrorStyle.background)
            }
        }
        .background(MirrorStyle.background)
        .tint(MirrorStyle.accent)
        .sheet(isPresented: $showingSettings) { MirrorSettingsView(model: model) }
        .alert(BrandIdentity.name, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MirrorMark().foregroundStyle(MirrorStyle.accent).frame(width: 28, height: 28)
            Text(BrandIdentity.name).font(.system(.title3, design: .rounded, weight: .semibold))
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(MirrorStyle.surface, in: Circle())
            }
            .accessibilityLabel(L10n.tr("Ayarlar"))
        }
        .padding(.top, 16)
    }

    private var status: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                Circle().fill(model.carPlayConnected ? MirrorStyle.accent : MirrorStyle.secondary).frame(width: 6, height: 6)
                Text(L10n.tr(model.carPlayConnected ? "CARPLAY BAĞLI" : "CARPLAY BEKLENİYOR"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundStyle(MirrorStyle.secondary)
            Text(model.captureTitle)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.body)
                .foregroundStyle(MirrorStyle.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        if model.broadcasting {
            VStack(spacing: 12) {
                if model.sessionState != .presenting && model.sessionState != .stopping && model.readyToPlay && model.supportsVideo == true {
                    Button { model.playInCar() } label: {
                        Label(L10n.tr("Görüntüyü yeniden bağla"), systemImage: "arrow.clockwise")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                }
                Button { model.stopBroadcast() } label: {
                    HStack(spacing: 12) {
                        if model.sessionState == .stopping { ProgressView() }
                        else { Image(systemName: "stop.fill").font(.system(size: 13)) }
                        Text(L10n.tr(model.sessionState == .stopping ? "Durduruluyor" : "Paylaşımı durdur"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1) }
                }
                .foregroundStyle(.white)
                .disabled(model.sessionState == .stopping)
            }
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Ekranını paylaş")).font(.headline).foregroundStyle(.white)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(L10n.tr("Başlatmak için dokun")).font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    }
                }
                Spacer(minLength: 8)
                BroadcastPicker()
                    .frame(width: 60, height: 60)
                    .background(MirrorStyle.accent, in: Circle())
                    .allowsHitTesting(model.storageReady)
                    .opacity(model.storageReady ? 1 : 0.4)
            }
            .padding(16)
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(MirrorStyle.accent.opacity(0.18), lineWidth: 1) }
        }
    }

    private var detail: String {
        switch model.sessionState {
        case .waitingForCar: return L10n.tr("CarPlay’e bağlanıp araç ekranında uygulamayı aç.")
        case .ready: return L10n.tr("Hazır olduğunda ekranını paylaş.")
        case .preparing: return L10n.tr("Ekran paylaşımı başlatılıyor.")
        case .captureReady, .connecting: return L10n.tr("Araç görüntüsü için bağlantı bekleniyor.")
        case .presenting: return L10n.tr("İzlemek istediğin uygulamaya geçebilirsin.")
        case .paused: return L10n.tr("Hazır olduğunda paylaşıma devam edebilirsin.")
        case .stopping: return L10n.tr("Yayın sonlandırılıyor.")
        case .interrupted, .failed: return L10n.tr("Ekran paylaşımını yeniden başlatabilirsin.")
        }
    }
}
