import SwiftUI

struct MirrorHomeView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback = MirrorModel.shared.playback
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("streamQuality", store: SharedPreferences.defaults) private var quality = StreamQuality.balanced.rawValue
    @AppStorage("audioMode", store: SharedPreferences.defaults) private var audioMode = StreamAudioMode.synchronized.rawValue
    @State private var showingGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            connectionCard
            TVConnectionButton(model: model)
            actions
            MediaSharingView(model: model)
            Button { showingGuide = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles.tv").font(.title2).foregroundStyle(MirrorStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.tr("Nasıl bağlanırım?")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("Google Cast · AirPlay").font(.caption).foregroundStyle(MirrorStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(MirrorStyle.secondary)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 78)
                    .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(.plain).accessibilityIdentifier("connection-guide")
            sessionDetails
            Text(BrandIdentity.tagline)
                .font(.footnote)
                .foregroundStyle(MirrorStyle.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .sheet(isPresented: $showingGuide) { ConnectionGuideView(model: model) }
        .alert(BrandIdentity.name, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(playback.tvName != nil ? MirrorStyle.accent : MirrorStyle.secondary).frame(width: 6, height: 6)
                Text(playback.tvName ?? "TV · AIRPLAY")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .tracking(L10n.appLanguage.allowsLetterSpacing ? 1.2 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(playback.tvName != nil ? MirrorStyle.accent : MirrorStyle.secondary)
            .padding(.bottom, 18)
            Text(model.broadcasting ? model.captureTitle : L10n.tr("Büyük ekranda daha fazlası."))
                .font(.system(.largeTitle, design: .default, weight: .semibold))
                .tracking(L10n.appLanguage.allowsLetterSpacing ? -1 : 0)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(model.broadcasting ? detail : L10n.tr("Anıların, videoların ve müziğin. Bir ekran seç, paylaşmaya başla."))
                .font(.subheadline)
                .foregroundStyle(MirrorStyle.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if model.broadcasting && !dynamicTypeSize.isAccessibilitySize {
                ScreenLinkIllustration(active: model.sessionState == .presenting)
                    .padding(.top, 14)
                    .padding(.bottom, -8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [MirrorStyle.raised.opacity(0.75), MirrorStyle.surface.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.hairline) }
    }

    @ViewBuilder
    private var actions: some View {
        if model.broadcasting {
            VStack(spacing: 12) {
                if model.sessionState != .presenting && model.sessionState != .stopping && model.readyToPlay && (playback.tvDevice != nil || model.externalScreenCount > 0) {
                    Button { model.playOnDisplay() } label: {
                        Label(L10n.tr("Görüntüyü yeniden bağla"), systemImage: "arrow.clockwise")
                    }.buttonStyle(MirivoButtonStyle(prominent: true))
                }
                Button { model.stopBroadcast() } label: {
                    HStack(spacing: 12) {
                        if model.sessionState == .stopping { ProgressView() }
                        else { Image(systemName: "stop.fill").font(.system(size: 14)) }
                        Text(L10n.tr(model.sessionState == .stopping ? "Durduruluyor" : "Paylaşımı durdur"))
                    }
                }
                .buttonStyle(MirivoButtonStyle())
                .disabled(model.sessionState == .stopping)
            }
        } else {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("Ekranını paylaş"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(L10n.tr("Başlatmak için dokun"))
                        .font(.footnote)
                        .foregroundStyle(MirrorStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                BroadcastPicker()
                    .frame(width: 72, height: 72)
                    .background(MirrorStyle.accent, in: RoundedRectangle(cornerRadius: 24))
                    .allowsHitTesting(model.storageReady)
                    .opacity(model.storageReady ? 1 : 0.4)
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.accent.opacity(0.23)) }
        }
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 18) {
            MirivoSectionLabel(title: L10n.tr("Tercihler"))
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            layout {
                preference("Yayın kalitesi", value: quality == StreamQuality.high.rawValue ? "Yüksek" : "Dengeli", icon: "slider.horizontal.3")
                preference("Ses", value: audioMode == StreamAudioMode.source.rawValue ? "Kaynak uygulamadan" : "Görüntüyle birlikte", icon: "waveform")
            }
        }.padding(.horizontal, 4)
    }

    private func preference(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(MirrorStyle.accent.opacity(0.8)).padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr(title)).font(.caption).foregroundStyle(MirrorStyle.secondary)
                Text(L10n.tr(value)).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.9))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: String {
        if playback.tvDevice != nil || model.externalScreenCount > 0 {
            switch model.sessionState {
            case .captureReady, .connecting: return L10n.tr("Görüntü bağlanıyor")
            default: break
            }
        }
        switch model.sessionState {
        case .waitingForDisplay: return L10n.tr("TV’ye bağlan")
        case .ready: return L10n.tr("Hazır olduğunda ekranını paylaş.")
        case .preparing: return L10n.tr("Ekran paylaşımı başlatılıyor.")
        case .captureReady, .connecting: return L10n.tr("TV bağlantısı")
        case .presenting: return L10n.tr("İzlemek istediğin uygulamaya geçebilirsin.")
        case .paused: return L10n.tr("Hazır olduğunda paylaşıma devam edebilirsin.")
        case .stopping: return L10n.tr("Yayın sonlandırılıyor.")
        case .interrupted, .failed: return L10n.tr("Ekran paylaşımını yeniden başlatabilirsin.")
        }
    }
}
