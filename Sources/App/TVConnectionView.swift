import SwiftUI
import AVKit

struct TVConnectionButton: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    var compact = false
    var playerChrome = false
    var presentPicker: (() -> Void)?
    @State private var showingTVs = false
    init(model: MirrorModel, compact: Bool = false, playerChrome: Bool = false, presentPicker: (() -> Void)? = nil) {
        self.playerChrome = playerChrome
        self.presentPicker = presentPicker
        self.model = model; self.playback = model.playback; self.compact = compact
    }
    var body: some View {
        Button {
            if let presentPicker { presentPicker() } else { showingTVs = true }
        } label: {
            if compact {
                Image(systemName: playback.displayConnection.symbol)
                    .font(.system(size: playerChrome ? 18 : 20, weight: .medium))
                    .frame(width: playerChrome ? 40 : 54, height: playerChrome ? 44 : 54)
                    .contentShape(Rectangle())
            } else {
                HStack(spacing: 12) {
                    Image(systemName: playback.displayConnection.symbol).font(.title3)
                    Text(playback.displayConnection.actionTitle).font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                }.padding(16).frame(minHeight: MirrorStyle.controlHeight)
                    .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(playerChrome && !playback.hasRemoteVideoOutput ? .white : MirrorStyle.accent)
        .accessibilityLabel(playback.displayConnection.title)
        .accessibilityValue(playback.displayConnection.connectedSummary)
        .accessibilityIdentifier("tv-connection")
        .sheet(isPresented: $showingTVs) { DisplayConnectionView(model: model) }
    }
}

struct DisplayConnectionView: View {
    let model: MirrorModel
    var body: some View { TVConnectionView(model: model) }
}

struct TVRouteStatusMark: View {
    let symbol: String
    var connected = true

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .font(.system(size: 19, weight: .medium))
            .frame(width: 26, height: 22)
            .foregroundStyle(MirrorStyle.accent)
            .frame(width: 54, height: 54)
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
            .overlay(alignment: .topTrailing) {
                if connected { Circle().fill(MirrorStyle.accent).frame(width: 8, height: 8).offset(x: -7, y: 7) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct TVConnectionView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @StateObject private var discovery = TVDiscovery()
    @Environment(\.dismiss) private var dismiss
    init(model: MirrorModel) { self.model = model; playback = model.playback }

    var body: some View {
        NavigationStack {
            List {
                if playback.hasActivePlayback && playback.hasRemoteVideoOutput {
                    Section {
                        HStack(spacing: 14) {
                            Image(systemName: playback.displayConnection.symbol)
                                .font(.title2).foregroundStyle(MirrorStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playback.displayConnection.destinationName).font(.headline)
                                Text(playback.displayPlaybackStatus()).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { playback.togglePlayPause() } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
                        }
                        Button { model.playOnPhone(); dismiss() } label: {
                            Label(L10n.tr("Telefonda oynat"), systemImage: "iphone").frame(minHeight: 44)
                        }.accessibilityIdentifier("connection-play-on-phone")
                    }
                }
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "airplayvideo").font(.title2).foregroundStyle(MirrorStyle.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AirPlay").font(.headline)
                            Text(playback.airPlayName ?? L10n.tr("Bir ekran seç"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Color.clear.frame(width: 56, height: 56)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .accessibilityHidden(true)
                    .overlay {
                        TVAirPlayPicker(onOpen: { model.disconnectTV(); model.returnToDisplay() })
                            .accessibilityIdentifier("connection-airplay")
                            .accessibilityLabel(L10n.tr("AirPlay hedefini değiştir"))
                            .accessibilityValue(playback.airPlayName ?? L10n.tr("Bir ekran seç"))
                    }
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(L10n.tr("Tüm ekranı veya MKV videolarını paylaşmak için Denetim Merkezi → Ekran Yansıtma yolundan AirPlay TV’ni seç."))
                }
                Section {
                    if let name = playback.tvName {
                        Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(MirrorStyle.accent)
                        Button(L10n.tr("TV bağlantısını kes"), role: .destructive) { model.disconnectTV() }
                            .accessibilityIdentifier("disconnect-tv-route")
                    }
                    ForEach(discovery.devices) { device in
                        Button {
                            model.connectTV(device.device); dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tv").font(.title3)
                                Text(device.name).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if playback.tvDevice?.isSameDevice(as: device.device) == true {
                                    Image(systemName: "checkmark").foregroundStyle(MirrorStyle.accent)
                                }
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("cast-device-\(device.id)")
                    }
                    if discovery.searching { ProgressView(L10n.tr("TV aranıyor…")).frame(minHeight: 44) }
                    else if discovery.unavailable {
                        Label(L10n.tr("Google Cast araması kullanılamıyor."), systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    } else if discovery.devices.isEmpty {
                        Label(L10n.tr("TV bulunamadı"), systemImage: "tv").foregroundStyle(.secondary)
                    }
                    Button(L10n.tr("Yeniden dene"), systemImage: "arrow.clockwise") { discovery.start() }
                        .accessibilityIdentifier("connection-scan-cast")
                } header: { Text("Google Cast") } footer: {
                    Text(L10n.tr("iPhone ve TV aynı Wi-Fi ağına bağlı olmalı."))
                }
                Section {
                    NavigationLink { ConnectionGuideContent() } label: {
                        Label(L10n.tr("Bağlantı yardımı"), systemImage: "questionmark.circle")
                    }.accessibilityIdentifier("tv-connection-help")
                    Button(L10n.tr("Ayarları aç"), systemImage: "gearshape") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 48)
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .navigationTitle(L10n.tr("Ekrana bağlan")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.tr("Kapat"))
                }
            }
        }
        .tint(MirrorStyle.accent).preferredColorScheme(.dark)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .onAppear { discovery.start() }.onDisappear { discovery.stop() }
    }
}

struct TVRouteStatusButton: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @State private var showingConnection = false
    init(model: MirrorModel) { self.model = model; playback = model.playback }
    var body: some View {
        Button { showingConnection = true } label: {
            TVRouteStatusMark(symbol: playback.displayConnection.primaryRoute?.symbol ?? "airplayvideo",
                              connected: playback.displayConnection.isConnected)
        }.buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Ekrana bağlan"))
            .accessibilityValue(playback.displayConnection.connectedSummary)
            .accessibilityIdentifier("tv-route-status")
            .sheet(isPresented: $showingConnection) { TVConnectionView(model: model) }
    }
}

struct TVConnectionStatusView: View {
    let model: MirrorModel
    var body: some View { TVConnectionView(model: model) }
}

private struct TVAirPlayPicker: UIViewRepresentable {
    var onOpen: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen) }
    func makeUIView(context: Context) -> FullRowAirPlayPickerView {
        let view = FullRowAirPlayPickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = UIColor(MirrorStyle.accent)
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: FullRowAirPlayPickerView, context: Context) { context.coordinator.onOpen = onOpen }
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onOpen: () -> Void
        init(onOpen: @escaping () -> Void) { self.onOpen = onOpen }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            // Merely opening or cancelling the route picker must not interrupt Cast playback.
            if AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay }) { onOpen() }
        }
    }
}

private final class FullRowAirPlayPickerView: AVRoutePickerView {
    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the system route action while extending its hit area across the row.
        for case let button as UIButton in subviews {
            button.frame = bounds
            button.contentHorizontalAlignment = .right
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 29)
        }
    }
}

struct ConnectionGuideView: View {
    let model: MirrorModel
    var initialRoute: ConnectedDisplayRoute? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let initialRoute {
            NavigationStack {
                Group {
                    if initialRoute == .carPlay { CarPlayGuideContent(model: model) }
                    else { ConnectionGuideContent(initialRoute: initialRoute) }
                }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel(L10n.tr("Kapat"))
                                .accessibilityIdentifier("close-connection-guide")
                        }
                    }
            }
            .tint(MirrorStyle.accent).preferredColorScheme(.dark)
        } else {
            TVConnectionView(model: model)
        }
    }
}

struct ConnectionGuideContent: View {
    private enum Route: String, CaseIterable { case cast = "Google Cast", airplay = "AirPlay" }
    @State private var route: Route = .cast

    init(initialRoute: ConnectedDisplayRoute? = nil) {
        _route = State(initialValue: initialRoute == .airPlay ? .airplay : .cast)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: route == .airplay ? "airplayvideo" : "tv")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(MirrorStyle.accent).padding(.top, 10)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { routeButtons }
                    VStack(alignment: .leading, spacing: 8) { routeButtons }
                }
                VStack(alignment: .leading, spacing: 24) {
                    step(1, text: "iPhone ve TV aynı Wi-Fi ağına bağlı olmalı.")
                    step(2, text: route == .cast
                         ? "TV’yi açıp Google Cast’i etkinleştir. TV görünmüyorsa iPhone Ayarlar’da Mirivo için Yerel Ağ iznini kontrol et."
                         : "Tüm ekranı veya MKV videolarını paylaşmak için Denetim Merkezi → Ekran Yansıtma yolundan AirPlay TV’ni seç.")
                    step(3, text: "Bir içerik seç. Oynatıcıdan duraklatabilir veya TV bağlantısını değiştirebilirsin.")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.tr("TV bulunamadı"), systemImage: "wifi.exclamationmark").font(.headline)
                    Text(L10n.tr("VPN veya misafir ağı cihazların birbirini bulmasını engelleyebilir."))
                    Text(L10n.tr("Google Cast ve AirPlay destekli TV’ler kullanılabilir. Yalnızca Miracast veya DLNA destekleyen TV’ler bu listede görünmez."))
                }.font(.footnote).foregroundStyle(MirrorStyle.secondary)
                    .padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(MirrorStyle.background)
            .navigationTitle(L10n.tr("Nasıl bağlanırım?")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
    private var routeButtons: some View {
        ForEach(Route.allCases, id: \.self) { item in
            Button { route = item } label: {
                Text(item.rawValue).font(.subheadline.weight(.semibold))
                    .fixedSize().padding(.horizontal, 14).frame(minHeight: 48)
                    .foregroundStyle(route == item ? MirrorStyle.background : .white)
                    .background(route == item ? MirrorStyle.accent : MirrorStyle.raised, in: Capsule())
            }.buttonStyle(.plain).accessibilityAddTraits(route == item ? .isSelected : [])
                .accessibilityIdentifier("guide-\(item.rawValue)")
        }
    }
    private func step(_ number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                .frame(width: 32, height: 32).background(MirrorStyle.accent.opacity(0.1), in: Circle()).accessibilityHidden(true)
            Text(L10n.tr(text)).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }.accessibilityElement(children: .combine)
    }
}

/// CarPlay has its own setup flow; it is not a selectable TV route.
struct CarPlayGuideContent: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "car.side.fill")
                        Text("CarPlay").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "parkingsign.circle").font(.title2)
                    }
                    .foregroundStyle(MirrorStyle.accent)
                    HStack(spacing: 18) {
                        Image(systemName: "iphone")
                            .font(.system(size: 44, weight: .ultraLight))
                        Image(systemName: "arrow.right")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(MirrorStyle.accent)
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(MirrorStyle.background.opacity(0.75))
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(MirrorStyle.accent.opacity(0.35))
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(MirrorStyle.accent)
                        }.frame(maxWidth: 164).frame(height: 102)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("CarPlay’de video izle"))
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.tr("Destekleyen araçlarda, park halindeyken."))
                            .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [MirrorStyle.accent.opacity(0.16), MirrorStyle.surface],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28))
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.accent.opacity(0.18)) }

                if model.carPlayConnected {
                    Label(L10n.tr("CarPlay bağlı"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.accent)
                        .accessibilityIdentifier("carplay-guide-connected")
                }

                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.tr("Nasıl bağlanırım?")).font(.headline)
                    instruction(1, text: "CarPlay’e bağlanıp araç ekranında uygulamayı aç.")
                    Divider().overlay(MirrorStyle.hairline)
                    instruction(2, text: "CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir.")
                }
                .padding(20)
                .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 24))

                if model.supportsVideo == false && model.carPlayConnected && !model.hasCarPlayDisplay {
                    Label(L10n.tr("Bu araç CarPlay video oynatmayı desteklemiyor."), systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.playback.playsOnPhone && model.hasCarPlayDisplay {
                    Button { model.returnToDisplay() } label: {
                        Label(L10n.tr("Bu ekranda oynat"), systemImage: "play.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }.buttonStyle(MirivoButtonStyle(prominent: true))
                }
            }
            .padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background)
        .navigationTitle("CarPlay").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("carplay-guide")
    }

    private func instruction(_ number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(MirrorStyle.accent)
                .frame(width: 30, height: 30)
                .background(MirrorStyle.accent.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            Text(L10n.tr(text)).font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
