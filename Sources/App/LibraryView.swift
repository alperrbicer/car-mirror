import SwiftUI
import AVKit

struct LibraryView: View {
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var purchases = PurchaseStore.shared
    @ObservedObject private var model = MirrorModel.shared
    @State private var adding = false
    @State private var showingPro = false
    var body: some View {
        List {
            if let title = model.mediaTitle {
                Section {
                    NavigationLink { MediaPlayerScreen(model: model) } label: {
                        Label(title, systemImage: "play.circle.fill").foregroundStyle(MirrorStyle.accent)
                    }
                } header: { Text(L10n.tr("Şimdi oynatılıyor")) }
            }
            if library.sources.isEmpty {
                ContentUnavailableView {
                    Label(L10n.tr("Kaynakların burada"), systemImage: "rectangle.stack")
                } description: { Text(L10n.tr("Bir oynatma listesi, yayın bağlantısı veya IPTV sunucusu ekle.")) }
                actions: { Button(L10n.tr("Kaynak ekle")) { add() }.buttonStyle(.borderedProminent) }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(library.sources) { source in
                    NavigationLink { ChannelListView(source: source) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: source.kind == .xtream ? "server.rack" : "play.rectangle")
                                .foregroundStyle(MirrorStyle.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.name).font(.headline)
                                Text(L10n.tr(source.kind == .xtream ? "IPTV sunucusu" : source.kind == .playlist ? "Oynatma listesi" : "Yayın bağlantısı"))
                                    .font(.caption).foregroundStyle(MirrorStyle.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                    .swipeActions {
                        Button(L10n.tr("Sil"), role: .destructive) {
                            do { try library.delete(source) } catch { library.message = L10n.tr("Kaynak silinemedi. Yeniden dene.") }
                        }
                    }
                    .listRowBackground(MirrorStyle.surface)
                }
            }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(L10n.tr("Kaynaklar"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { add() } label: { Image(systemName: "plus") }.accessibilityLabel(L10n.tr("Kaynak ekle")) } }
        .sheet(isPresented: $adding) { AddSourceView() }
        .sheet(isPresented: $showingPro) { NavigationStack { ProView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("Bitti")) { showingPro = false } } } } }
        .alert(BrandIdentity.name, isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button(L10n.tr("Tamam")) { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
    private func add() {
        if purchases.access.canAddSource(count: library.sources.count) { adding = true } else { showingPro = true }
    }
}

private struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var kind: MediaSourceKind = .playlist
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.tr("Kaynak türü"), selection: $kind) {
                        Text(L10n.tr("M3U oynatma listesi")).tag(MediaSourceKind.playlist)
                        Text(L10n.tr("Yayın bağlantısı")).tag(MediaSourceKind.stream)
                        Text(L10n.tr("Xtream Codes")).tag(MediaSourceKind.xtream)
                    }
                    TextField(L10n.tr("Kaynak adı"), text: $name).textInputAutocapitalization(.words)
                    TextField(kind == .xtream ? "https://server.example" : "https://example.com/playlist.m3u", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(L10n.tr("Kaynak adresi"))
                    if kind == .xtream {
                        TextField(L10n.tr("Kullanıcı adı"), text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField(L10n.tr("Parola"), text: $password)
                    }
                } footer: { Text(L10n.tr("Mirivo içerik sağlamaz. Erişim hakkına sahip olduğun kaynakları ekleyebilirsin. Adres ve giriş bilgileri cihazındaki Keychain’de saklanır.")) }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(L10n.tr("Kaynak ekle")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Vazgeç")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Ekle")) { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || address.isEmpty || (kind == .xtream && (username.isEmpty || password.isEmpty)))
                }
            }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
    }
    private func save() {
        do {
            let url = try MediaURL.validate(address)
            try SourceLibrary.shared.add(name: name, kind: kind, secret: SourceSecret(url: url,
                username: kind == .xtream ? username : nil, password: kind == .xtream ? password : nil), access: PurchaseStore.shared.access)
            dismiss()
        } catch { message = L10n.tr("Kaynak eklenemedi. Adresi ve giriş bilgilerini kontrol et.") }
    }
}

private struct ChannelListView: View {
    let source: MediaSource
    @State private var channels: [MediaChannel] = []
    @State private var query = ""
    @State private var loading = false
    @State private var message: String?
    @State private var showingPlayer = false
    @State private var refreshID = UUID()
    private var filtered: [MediaChannel] { query.isEmpty ? channels : channels.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.group.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            if loading { ProgressView(L10n.tr("Kaynak yükleniyor…")).frame(maxWidth: .infinity) }
            if let message {
                ContentUnavailableView { Label(message, systemImage: "wifi.exclamationmark") }
                    actions: { Button(L10n.tr("Yeniden dene")) { refreshID = UUID() } }
            }
            ForEach(filtered) { channel in
                Button {
                    MirrorModel.shared.playMedia(channel)
                    showingPlayer = MirrorModel.shared.mediaTitle != nil
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.title).foregroundStyle(.primary)
                            if !channel.group.isEmpty { Text(channel.group).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(); Image(systemName: "play.circle").foregroundStyle(MirrorStyle.accent)
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.tr("Kanal veya grup ara"))
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: .shared) }
        .task(id: refreshID) {
            loading = true; message = nil
            defer { loading = false }
            do { channels = try await SourceLibrary.shared.channels(for: source) }
            catch is CancellationError { }
            catch { message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
        }
    }
}

struct NativeVideoView: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsControls = true
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsControls
    }
}

struct MediaPlayerScreen: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var vehicleMode = false
    @State private var showingPro = false
    var body: some View {
        VStack(spacing: 20) {
            NativeVideoView(player: model.playback.player).aspectRatio(16 / 9, contentMode: .fit)
            Text(model.mediaTitle ?? L10n.tr("Oynatıcı")).font(.headline).lineLimit(2).padding(.horizontal)
            Button {
                if purchases.access.fullAccess { vehicleMode = true } else { showingPro = true }
            } label: { Label(L10n.tr("Araç modu"), systemImage: "car.side").frame(minHeight: 44) }
            Spacer(minLength: 0)
            Button(L10n.tr("Oynatmayı durdur"), role: .destructive) { model.stopPlayback() }.padding()
        }
        .background(MirrorStyle.background).navigationTitle(L10n.tr("Oynatıcı")).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $vehicleMode) { VehicleModeView(model: model) }
        .sheet(isPresented: $showingPro) { NavigationStack { ProView() } }
        .alert(BrandIdentity.name, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct VehicleModeView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback = MirrorModel.shared.playback
    @Environment(\.dismiss) private var dismiss
    @State private var previousIdleState = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text(model.mediaTitle ?? BrandIdentity.name).font(.headline).lineLimit(1)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 60, height: 60) }.accessibilityLabel(L10n.tr("Kapat"))
                }.padding(.horizontal, 24)
                NativeVideoView(player: playback.player).frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 32) {
                    Button { playback.togglePlayPause() } label: {
                        Label(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"), systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button { model.stopPlayback(); dismiss() } label: { Label(L10n.tr("Durdur"), systemImage: "stop.fill") }
                }.font(.title3.weight(.semibold)).frame(minHeight: 72).frame(maxWidth: .infinity).background(MirrorStyle.surface)
            }.background(.black).foregroundStyle(.white)
        }
        .onAppear { previousIdleState = UIApplication.shared.isIdleTimerDisabled; UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = previousIdleState }
        .statusBarHidden(true)
    }
}
