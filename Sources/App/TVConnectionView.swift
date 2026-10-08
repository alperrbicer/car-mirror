import SwiftUI
import AVKit

struct TVConnectionButton: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    var compact = false
    @State private var showingTVs = false
    init(model: MirrorModel, compact: Bool = false) {
        self.model = model; self.playback = model.playback; self.compact = compact
    }
    var body: some View {
        Button { showingTVs = true } label: {
            if compact {
                Image(systemName: playback.tvName == nil ? "tv" : "tv.fill").frame(width: 44, height: 44)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "tv").font(.title3)
                    Text(playback.tvName ?? L10n.tr("TV’ye bağlan")).font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }.padding(16).frame(minHeight: MirrorStyle.controlHeight)
                    .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .buttonStyle(.plain).foregroundStyle(MirrorStyle.accent)
        .accessibilityLabel(L10n.tr("TV bağlantısı")).accessibilityValue(playback.tvName ?? "")
        .accessibilityIdentifier("tv-connection")
        .sheet(isPresented: $showingTVs) { TVConnectionView(model: model) }
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
                Section {
                    Text(L10n.tr("iPhone ve TV aynı Wi-Fi ağına bağlı olmalı."))
                        .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    if let name = playback.tvName {
                        Label(name, systemImage: "tv.fill").foregroundStyle(MirrorStyle.accent)
                        Button(L10n.tr("iPhone’da oynat")) { model.disconnectTV(); dismiss() }
                    }
                }
                Section {
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
                    NavigationLink { ConnectionGuideContent() } label: {
                        Label(L10n.tr("Nasıl bağlanırım?"), systemImage: "questionmark.circle")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("tv-connection-help")
                    Button(L10n.tr("Ayarları aç"), systemImage: "gearshape") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.frame(minHeight: 44)
                }
            }
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .navigationTitle(L10n.tr("TV bağlantısı")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
        }
        .tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
        .onAppear { discovery.start() }.onDisappear { discovery.stop() }
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ConnectionGuideContent()
                .safeAreaInset(edge: .bottom) {
                    TVConnectionButton(model: model).padding(20).background(MirrorStyle.background)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
}

struct ConnectionGuideContent: View {
    private enum Route: String, CaseIterable { case cast = "Google Cast", airplay = "AirPlay" }
    @State private var route: Route = .cast
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: route == .airplay ? "airplay.video" : "tv")
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
