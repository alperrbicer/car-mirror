import SwiftUI

struct MirrorHomeView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback = MirrorModel.shared.playback
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("streamQuality", store: SharedPreferences.defaults) private var quality = StreamQuality.balanced.rawValue
    @AppStorage("audioMode", store: SharedPreferences.defaults) private var audioMode = StreamAudioMode.synchronized.rawValue
    @State private var showingGuide = false
    @State private var showingCarPlay = false
    @State private var showingDisplays = false
    @ObservedObject private var purchases = PurchaseStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            connectionCard
            actions
            MediaSharingView(model: model)
            Button { showingGuide = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: playback.displayConnection.symbol).font(.title2).foregroundStyle(MirrorStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.tr("Nasıl bağlanırım?")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("Google Cast · AirPlay · CarPlay").font(.caption).foregroundStyle(MirrorStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(MirrorStyle.secondary)
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
        .sheet(isPresented: $showingCarPlay) { ConnectionGuideView(model: model, initialRoute: .carPlay) }
        .sheet(isPresented: $showingDisplays) {
            if playback.displayConnection.primaryRoute == .carPlay { TVConnectionView(model: model) }
            else { DisplayConnectionView(model: model) }
        }
        .alert(BrandIdentity.name, isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if playback.displayConnection.isConnected {
                HStack(spacing: 8) {
                    Circle().fill(MirrorStyle.accent).frame(width: 6, height: 6)
                    Text(playback.displayConnection.connectedSummary)
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(MirrorStyle.accent)
                .padding(.bottom, 14)
            }
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if model.broadcasting {
                        Text(model.captureTitle)
                    } else {
                        Text("Smart TV.") + Text("\nCarPlay.").foregroundColor(MirrorStyle.accent)
                    }
                }
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .tracking(L10n.appLanguage.allowsLetterSpacing ? -1.2 : 0)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                Text(model.broadcasting ? detail : L10n.tr("Büyük ekranda daha fazlası."))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            if !dynamicTypeSize.isAccessibilitySize {
                ScreenLinkIllustration(active: playback.displayConnection.isConnected || model.sessionState == .presenting)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            destinations
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 22 : 0)
        }
        .padding(20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(colors: [Color(red: 0.075, green: 0.16, blue: 0.15), MirrorStyle.surface, Color(red: 0.045, green: 0.07, blue: 0.075)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(LinearGradient(colors: [MirrorStyle.accent.opacity(0.42), MirrorStyle.hairline, MirrorStyle.accent.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
    }

    private var destinations: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            Button { showingDisplays = true } label: {
                destination("Smart TV", detail: "Cast · AirPlay", symbol: "tv")
            }
            .accessibilityLabel("Smart TV")
            .accessibilityValue(playback.displayConnection.primaryRoute == .carPlay ? "" : playback.displayConnection.connectedSummary)
            .accessibilityIdentifier("tv-connection")
            Button { showingCarPlay = true } label: {
                destination("CarPlay", detail: L10n.tr("Park halindeyken"), symbol: "car.side.fill", prominent: true)
            }.accessibilityIdentifier("home-carplay")
        }.buttonStyle(MirivoPressButtonStyle())
    }

    private func destination(_ title: String, detail: String, symbol: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 25, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(prominent ? Color.black.opacity(0.08) : MirrorStyle.accent.opacity(0.10), in: Circle())
            }
            .frame(height: 30)
            .foregroundStyle(prominent ? MirrorStyle.background : MirrorStyle.accent)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(prominent ? MirrorStyle.background : .white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(prominent ? MirrorStyle.background.opacity(0.75) : Color.white.opacity(0.72))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14).frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: prominent
                                     ? [Color(red: 0.65, green: 0.97, blue: 0.85), MirrorStyle.accent]
                                     : [Color(red: 0.10, green: 0.25, blue: 0.22), Color(red: 0.055, green: 0.15, blue: 0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(prominent ? Color.white.opacity(0.3) : MirrorStyle.accent.opacity(0.32))
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var actions: some View {
        if model.broadcasting {
            VStack(spacing: 12) {
                if model.sessionState != .presenting && model.sessionState != .stopping && model.readyToPlay && (model.supportsVideo == true || playback.tvDevice != nil || model.externalScreenCount > 0) {
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
                        .accessibilityIdentifier("home-share-title")
                    Text(L10n.tr("Başlatmak için dokun"))
                        .font(.footnote)
                        .foregroundStyle(MirrorStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Group {
                    if purchases.access.fullAccess {
                        BroadcastPicker().allowsHitTesting(model.storageReady)
                            .opacity(model.storageReady ? 1 : 0.4)
                    } else {
                        Button { model.presentMembershipOffer() } label: {
                            Image(systemName: "rectangle.on.rectangle").font(.title2)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.accessibilityLabel(L10n.tr("Ekranını paylaş"))
                            .accessibilityIdentifier("share-screen-membership")
                    }
                }
                .frame(width: 60, height: 60)
                .foregroundStyle(MirrorStyle.accent)
                .background(purchases.access.fullAccess ? MirrorStyle.accent : MirrorStyle.raised,
                            in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.accent.opacity(0.23)).allowsHitTesting(false) }
        }
    }

    private var sessionDetails: some View {
        return VStack(alignment: .leading, spacing: 12) {
            MirivoSectionLabel(title: L10n.tr("Ekranını paylaş"))
            VStack(spacing: 0) {
                preferenceMenu(title: "Yayın kalitesi", value: quality == StreamQuality.high.rawValue ? "Yüksek" : "Dengeli") {
                    Picker(L10n.tr("Yayın kalitesi"), selection: $quality) {
                        Text(L10n.tr("Dengeli")).tag(StreamQuality.balanced.rawValue)
                        Text(L10n.tr("Yüksek")).tag(StreamQuality.high.rawValue)
                    }
                }
                Divider().overlay(MirrorStyle.hairline)
                preferenceMenu(title: "Ses", value: audioMode == StreamAudioMode.source.rawValue ? "Kaynak uygulamadan" : "Görüntüyle birlikte") {
                    Picker(L10n.tr("Ses"), selection: $audioMode) {
                        Text(L10n.tr("Görüntüyle birlikte")).tag(StreamAudioMode.synchronized.rawValue)
                        Text(L10n.tr("Kaynak uygulamadan")).tag(StreamAudioMode.source.rawValue)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func preferenceMenu<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(L10n.tr(title)).font(.subheadline)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Menu {
                content().pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.tr(value)).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.tr(title))
            .accessibilityValue(L10n.tr(value))
            .accessibilityIdentifier(title == "Ses" ? "home-audio" : "home-quality")
        }
    }

    private var detail: String {
        if model.supportsVideo == true || playback.tvDevice != nil || model.externalScreenCount > 0 {
            switch model.sessionState {
            case .captureReady, .connecting: return L10n.tr("Görüntü bağlanıyor")
            default: break
            }
        }
        switch model.sessionState {
        case .waitingForDisplay: return model.displayRequiredMessage
        case .ready: return L10n.tr("Hazır olduğunda ekranını paylaş.")
        case .preparing: return L10n.tr("Ekran paylaşımı başlatılıyor.")
        case .captureReady, .connecting: return playback.displayConnection.title
        case .presenting: return L10n.tr("İzlemek istediğin uygulamaya geçebilirsin.")
        case .paused: return L10n.tr("Hazır olduğunda paylaşıma devam edebilirsin.")
        case .stopping: return L10n.tr("Yayın sonlandırılıyor.")
        case .interrupted, .failed: return L10n.tr("Ekran paylaşımını yeniden başlatabilirsin.")
        }
    }
}
