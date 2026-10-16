import SwiftUI
import AVKit

struct TVConnectionButton: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    var compact = false
    var presentPicker: (() -> Void)?
    @State private var showingTVs = false
    init(model: MirrorModel, compact: Bool = false, presentPicker: (() -> Void)? = nil) {
        self.presentPicker = presentPicker
        self.model = model; self.playback = model.playback; self.compact = compact
    }
    var body: some View {
        Button {
            if let presentPicker { presentPicker() } else { showingTVs = true }
        } label: {
            if compact {
                Image(systemName: playback.displayConnection.symbol)
                    .frame(width: 54, height: 54)
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
        .buttonStyle(.plain).foregroundStyle(MirrorStyle.accent)
        .accessibilityLabel(playback.displayConnection.title)
        .accessibilityValue(playback.displayConnection.connectedSummary)
        .accessibilityIdentifier("tv-connection")
        .sheet(isPresented: $showingTVs) { DisplayConnectionView(model: model) }
    }
}

/// Capture the entry point when the sheet opens. A disconnect can then dismiss
/// its status sheet without replacing it with a discovery screen mid-action.
struct DisplayConnectionView: View {
    let model: MirrorModel
    @State private var showsStatus: Bool

    init(model: MirrorModel) {
        self.model = model
        _showsStatus = State(initialValue: model.playback.displayConnection.isConnected)
    }

    var body: some View {
        if showsStatus { TVConnectionStatusView(model: model) }
        else { TVConnectionView(model: model) }
    }
}

struct TVRouteStatusMark: View {
    let symbol: String

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
                Circle().fill(MirrorStyle.accent).frame(width: 8, height: 8).offset(x: -7, y: 7)
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
                Group {
                    Section("CarPlay") {
                        if model.carPlayConnected {
                            Label(L10n.tr("CarPlay bağlı"), systemImage: "car.side")
                                .foregroundStyle(MirrorStyle.accent)
                        }
                        NavigationLink { ConnectionGuideContent(initialRoute: .carPlay) } label: {
                            Label(L10n.tr("CarPlay’e bağlanıp araç ekranında uygulamayı aç."), systemImage: "car.side")
                        }
                    }
                    Section {
                        Text(L10n.tr("iPhone ve TV aynı Wi-Fi ağına bağlı olmalı."))
                            .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        if let name = playback.tvName {
                            Label(name, systemImage: "tv.fill").foregroundStyle(MirrorStyle.accent)
                            Button(L10n.tr("iPhone’da oynat")) { model.disconnectTV(); dismiss() }
                        }
                        ForEach(discovery.devices) { device in
                            Button {
                                model.connectTV(device.device)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "tv")
                                    Text(device.name).foregroundStyle(.primary)
                                    Spacer()
                                    if playback.tvDevice?.isSameDevice(as: device.device) == true { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44)
                            }
                        }
                        if discovery.searching { ProgressView(L10n.tr("TV aranıyor…")) }
                        else if discovery.unavailable { Label(L10n.tr("Google Cast araması kullanılamıyor."), systemImage: "wifi.exclamationmark").foregroundStyle(.secondary) }
                        else if discovery.devices.isEmpty { Text(L10n.tr("TV bulunamadı")).foregroundStyle(.secondary) }
                        Button(L10n.tr("Yeniden dene")) { discovery.start() }
                    } header: { Text("Google Cast") } footer: {
                        Text(L10n.tr("TV’yi açıp Google Cast’i etkinleştir. TV görünmüyorsa iPhone Ayarlar’da Mirivo için Yerel Ağ iznini kontrol et."))
                    }
                    Section("AirPlay") {
                        HStack {
                            Label("AirPlay", systemImage: "airplay.video")
                            Spacer()
                            TVAirPlayPicker(onOpen: { model.disconnectTV() }).frame(width: 52, height: 52)
                        }
                        Text(L10n.tr("Tüm ekranı veya MKV videolarını paylaşmak için Denetim Merkezi → Ekran Yansıtma yolundan AirPlay TV’ni seç."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Text(L10n.tr("Google Cast ve AirPlay destekli TV’ler kullanılabilir. Yalnızca Miracast veya DLNA destekleyen TV’ler bu listede görünmez."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        NavigationLink { ConnectionGuideContent(initialRoute: playback.displayConnection.primaryRoute) } label: {
                            Label(L10n.tr("Nasıl bağlanırım?"), systemImage: "questionmark.circle")
                                .frame(minHeight: 44)
                        }.accessibilityIdentifier("tv-connection-help")
                        Button(L10n.tr("Ayarları aç"), systemImage: "gearshape") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.frame(minHeight: 44)
                    }
                }.listRowBackground(MirrorStyle.surface)
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, MirrorStyle.controlHeight)
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .navigationTitle(L10n.tr("Ekran bağlantısı")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
        }
        .tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
        .onAppear { discovery.start() }.onDisappear { discovery.stop() }
    }
}

struct TVRouteStatusButton: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @State private var showingStatus = false

    init(model: MirrorModel) {
        self.model = model
        playback = model.playback
    }

    private var routes: [ConnectedDisplayRoute] { ConnectedDisplayRoute.connected(to: model) }

    @ViewBuilder
    var body: some View {
        if let route = routes.first {
            Button { showingStatus = true } label: {
                TVRouteStatusMark(symbol: route.symbol)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.displayConnection.title)
            .accessibilityValue(playback.displayConnection.connectedSummary)
            .accessibilityIdentifier("tv-route-status")
            .sheet(isPresented: $showingStatus) { TVConnectionStatusView(model: model) }
        }
    }
}

struct TVConnectionStatusView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDisconnectHelp = false
    @State private var disconnectHelpRoute = ConnectedDisplayRoute.carPlay
    @State private var showingOtherDisplays = false

    init(model: MirrorModel) {
        self.model = model
        playback = model.playback
    }

    private var routes: [ConnectedDisplayRoute] { ConnectedDisplayRoute.connected(to: model) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    ForEach(routes) { route in
                        routeStatus(route)
                    }
                    if playback.hasActivePlayback || model.broadcasting || model.probeStartedAt != nil {
                        Button { model.stopBroadcast() } label: {
                            Label(L10n.tr("Oynatmayı durdur"), systemImage: "stop.fill")
                        }
                        .buttonStyle(MirivoButtonStyle())
                        .accessibilityIdentifier("stop-display-playback")
                    }
                    Button { showingOtherDisplays = true } label: {
                        Label(L10n.tr("Başka bir ekrana bağlan"), systemImage: "display")
                    }
                    .buttonStyle(MirivoButtonStyle())
                    .accessibilityIdentifier("connect-another-display")
                }.padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MirrorStyle.background)
            .navigationTitle(playback.displayConnection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
            .alert(L10n.tr("Bağlantıyı kesme adımları"), isPresented: $showingDisconnectHelp) {
                Button(L10n.tr("Tamam"), role: .cancel) {}
            } message: {
                Text(L10n.tr(disconnectHelpRoute == .carPlay
                    ? "Kablolu CarPlay için USB kablosunu çıkar. Kablosuz CarPlay için araç ekranından bağlantıyı kes. CarPlay Simulator kullanıyorsan simülatörde bağlantıyı sonlandır."
                    : "AirPlay için Denetim Merkezi → Ekran Yansıtma → Yansıtmayı Durdur yolunu izle. Kablolu ekran bağlantısında HDMI/USB adaptörünü çıkar."))
            }
        }
        .tint(MirrorStyle.accent)
        .preferredColorScheme(.dark)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(540), .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingOtherDisplays) { TVConnectionView(model: model) }
        .onChange(of: routes) { _, routes in
            if routes.isEmpty { dismiss() }
        }
    }

    private func routeStatus(_ route: ConnectedDisplayRoute) -> some View {
        VStack(spacing: 22) {
            Image(systemName: route.symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MirrorStyle.accent)
                .frame(width: 84, height: 84)
                .background(MirrorStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 26))
            VStack(spacing: 8) {
                Text(playback.displayConnection.destinationName(for: route)).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Label(playback.displayPlaybackStatus(for: route), systemImage: "circle.fill")
                    .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    .labelStyle(StatusDotLabelStyle())
                    .multilineTextAlignment(.center)
            }
            if route == .carPlay {
                Text(L10n.tr(model.supportsVideo != false || model.hasCarPlayDisplay
                             ? "CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir."
                             : "Bu araç CarPlay video oynatmayı desteklemiyor."))
                    .font(.footnote).foregroundStyle(MirrorStyle.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                disconnectHelpButton(for: route)
            } else if route == .cast {
                Button {
                    model.disconnectTV()
                } label: {
                    Label(L10n.tr("TV bağlantısını kes"), systemImage: "tv.slash")
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(MirivoButtonStyle(prominent: true))
                .accessibilityIdentifier("disconnect-tv-route")
            } else if route == .airPlay {
                Text(L10n.tr("AirPlay hedefini değiştirmek veya iPhone’a dönmek için aşağıdaki sistem menüsünü kullan."))
                    .font(.footnote).foregroundStyle(MirrorStyle.secondary).multilineTextAlignment(.center)
                HStack {
                    Label(L10n.tr("iPhone’da oynat"), systemImage: "iphone")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    TVAirPlayPicker(onOpen: {}).frame(width: 60, height: 60)
                        .accessibilityLabel(L10n.tr("AirPlay hedefini değiştir"))
                        .accessibilityIdentifier("disconnect-airplay-route")
                }
                .padding(.leading, 20).padding(.trailing, 6)
                .foregroundStyle(.white)
                .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 18))
                if model.hasTVDisplay { disconnectHelpButton(for: route) }
            } else {
                disconnectHelpButton(for: route)
            }
        }
    }

    private func disconnectHelpButton(for route: ConnectedDisplayRoute) -> some View {
        Button {
            disconnectHelpRoute = route
            showingDisconnectHelp = true
        } label: {
            Label(L10n.tr("Bağlantıyı kesme adımları"), systemImage: "link")
        }
        .buttonStyle(MirivoButtonStyle(prominent: true))
        .accessibilityIdentifier("disconnect-\(route.rawValue)-help")
    }
}

private struct StatusDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(MirrorStyle.accent)
            configuration.title
        }
    }
}

private struct TVAirPlayPicker: UIViewRepresentable {
    var onOpen: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen) }
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = UIColor(MirrorStyle.accent)
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) { context.coordinator.onOpen = onOpen }
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        var onOpen: () -> Void
        init(onOpen: @escaping () -> Void) { self.onOpen = onOpen }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            // Merely opening or cancelling the route picker must not interrupt Cast playback.
            if AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay }) { onOpen() }
        }
    }
}

struct ConnectionGuideView: View {
    @ObservedObject var model: MirrorModel
    var initialRoute: ConnectedDisplayRoute? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ConnectionGuideContent(initialRoute: initialRoute ?? model.playback.displayConnection.primaryRoute)
                .safeAreaInset(edge: .bottom) {
                    TVConnectionButton(model: model).padding(20).background(MirrorStyle.background)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
}

struct ConnectionGuideContent: View {
    private enum Route: String, CaseIterable { case cast = "Google Cast", airplay = "AirPlay", carplay = "CarPlay" }
    @State private var route: Route = .cast

    init(initialRoute: ConnectedDisplayRoute? = nil) {
        _route = State(initialValue: initialRoute == .carPlay ? .carplay : initialRoute == .airPlay ? .airplay : .cast)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: route == .carplay ? "car.side" : route == .airplay ? "airplay.video" : "tv")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(MirrorStyle.accent).padding(.top, 10)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { routeButtons }
                    VStack(alignment: .leading, spacing: 8) { routeButtons }
                }
                VStack(alignment: .leading, spacing: 24) {
                    if route == .carplay {
                        step(1, text: "CarPlay’e bağlanıp araç ekranında uygulamayı aç.")
                        step(2, text: "CarPlay video, destekleyen araçlarda park halindeyken kullanılabilir.")
                    } else {
                        step(1, text: "iPhone ve TV aynı Wi-Fi ağına bağlı olmalı.")
                        step(2, text: route == .cast
                             ? "TV’yi açıp Google Cast’i etkinleştir. TV görünmüyorsa iPhone Ayarlar’da Mirivo için Yerel Ağ iznini kontrol et."
                             : "Tüm ekranı veya MKV videolarını paylaşmak için Denetim Merkezi → Ekran Yansıtma yolundan AirPlay TV’ni seç.")
                        step(3, text: "Bir içerik seç. Oynatıcıdan duraklatabilir veya TV bağlantısını değiştirebilirsin.")
                    }
                }
                if route != .carplay {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.tr("TV bulunamadı"), systemImage: "wifi.exclamationmark").font(.headline)
                        Text(L10n.tr("VPN veya misafir ağı cihazların birbirini bulmasını engelleyebilir."))
                        Text(L10n.tr("Google Cast ve AirPlay destekli TV’ler kullanılabilir. Yalnızca Miracast veya DLNA destekleyen TV’ler bu listede görünmez."))
                    }.font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        .padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                }
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
