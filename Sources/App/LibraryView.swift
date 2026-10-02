import SwiftUI
import AVKit

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var purchases = PurchaseStore.shared
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    @State private var adding = false
    @State private var editing: SourceEditDraft?
    @State private var showingPro = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr(library.sources.isEmpty ? "Kaynakların burada" : "Kaynaklar"))
                    .font(.largeTitle.weight(.semibold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.tr("Bir oynatma listesi, yayın bağlantısı veya IPTV sunucusu ekle."))
                    .font(.subheadline).foregroundStyle(MirrorStyle.secondary).lineSpacing(4)
            }.fixedSize(horizontal: false, vertical: true)
            if let title = model.mediaTitle, playback.hasActivePlayback {
                NavigationLink { MediaPlayerScreen(model: model) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(MirrorStyle.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.tr(playback.state == .playing ? "Şimdi oynatılıyor" : playback.state == .loading ? "Yayın hazırlanıyor" : "Yayın duraklatıldı")).font(.caption).foregroundStyle(MirrorStyle.secondary)
                            Text(title).font(.headline).foregroundStyle(.white).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").foregroundStyle(MirrorStyle.accent)
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 86)
                        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
            }
            if library.sources.isEmpty {
                emptyLibrary
            } else {
                VStack(spacing: 12) {
                    ForEach(library.sources) { source in
                        HStack(spacing: 0) {
                            NavigationLink { ChannelListView(source: source) } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: source.kind == .xtream ? "server.rack" : "play.rectangle")
                                        .font(.title3).foregroundStyle(MirrorStyle.accent)
                                        .frame(width: 48, height: 52)
                                        .background(MirrorStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(source.name).font(.headline).foregroundStyle(.white)
                                        Text(L10n.tr(source.kind == .xtream ? "IPTV sunucusu" : source.kind == .playlist ? "Oynatma listesi" : "Yayın bağlantısı"))
                                            .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                    }
                                    Spacer(minLength: 4)
                                }
                                .padding(.leading, 16).padding(.vertical, 18)
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button(L10n.tr("Düzenle"), systemImage: "pencil") {
                                    do { editing = SourceEditDraft(source: source, secret: try SourceKeychain.read(source.id)) }
                                    catch { library.message = L10n.tr("Kaynaklar açılamadı. Lütfen yeniden dene.") }
                                }
                                Button(L10n.tr("Sil"), role: .destructive) {
                                    do { try library.delete(source) }
                                    catch { library.message = L10n.tr("Kaynak silinemedi. Yeniden dene.") }
                                }
                            } label: {
                                Image(systemName: "ellipsis").font(.body.weight(.semibold))
                                    .foregroundStyle(MirrorStyle.secondary).frame(width: 48, height: 58)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(source.name)
                        }
                        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(MirrorStyle.hairline) }
                    }
                }
            }
            Button { add() } label: {
                HStack { Text(L10n.tr("Kaynak ekle")); Spacer(); Image(systemName: "plus") }
            }
            .buttonStyle(MirivoButtonStyle(prominent: true))
            .accessibilityIdentifier("add-source")
        }
        .sheet(isPresented: $adding) { SourceEditorView() }
        .sheet(item: $editing) { draft in SourceEditorView(source: draft.source, secret: draft.secret) }
        .sheet(isPresented: $showingPro) {
            NavigationStack {
                ProView().toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button { showingPro = false } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr("Bitti"))
                } }
            }
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button(L10n.tr("Tamam")) { library.message = nil }
        } message: { Text(library.message ?? "") }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 17).fill(MirrorStyle.raised.opacity(0.4))
                    .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(MirrorStyle.hairline) }
                    .frame(width: 158, height: 98).rotationEffect(.degrees(-10)).offset(x: -24, y: -12)
                RoundedRectangle(cornerRadius: 17).fill(MirrorStyle.surface)
                    .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(MirrorStyle.accent.opacity(0.3)) }
                    .frame(width: 158, height: 98).rotationEffect(.degrees(7)).offset(x: 24, y: 10)
                Image(systemName: "play.fill").font(.system(size: 25, weight: .medium))
                    .foregroundStyle(MirrorStyle.accent).offset(x: 26, y: 10)
            }.frame(maxWidth: .infinity).frame(height: 180).accessibilityHidden(true)
            VStack(spacing: 0) {
                sourceType("Oynatma listesi", detail: "M3U", icon: "list.bullet.rectangle")
                Rectangle().fill(MirrorStyle.hairline).frame(height: 1)
                sourceType("Yayın bağlantısı", detail: "URL", icon: "link")
                Rectangle().fill(MirrorStyle.hairline).frame(height: 1)
                sourceType("IPTV sunucusu", detail: "Xtream Codes", icon: "server.rack")
            }.padding(.horizontal, 22).padding(.bottom, 8)
        }
        .background(MirrorStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.hairline) }
    }

    private func sourceType(_ title: String, detail: String, icon: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 22)
                    .foregroundStyle(MirrorStyle.accent.opacity(0.8))
                Text(L10n.tr(title)).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text(detail).font(.caption).foregroundStyle(MirrorStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 4)
            .accessibilityElement(children: .combine)
    }

    private func add() {
        if purchases.access.canAddSource(count: library.sources.count) { adding = true } else { showingPro = true }
    }
}

private struct SourceEditDraft: Identifiable {
    let source: MediaSource
    let secret: SourceSecret
    var id: UUID { source.id }
}

private struct SourceEditorView: View {
    private let source: MediaSource?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var kind: MediaSourceKind = .playlist
    @State private var message: String?
    init(source: MediaSource? = nil, secret: SourceSecret? = nil) {
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _kind = State(initialValue: source?.kind ?? .playlist)
        _address = State(initialValue: secret?.url.absoluteString ?? "")
        _username = State(initialValue: secret?.username ?? "")
        _password = State(initialValue: secret?.password ?? "")
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (kind != .xtream || (!username.isEmpty && !password.isEmpty))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.tr("Kaynak türü"), selection: $kind) {
                        Text(L10n.tr("M3U oynatma listesi")).tag(MediaSourceKind.playlist)
                        Text(L10n.tr("Yayın bağlantısı")).tag(MediaSourceKind.stream)
                        Text(L10n.tr("Xtream Codes")).tag(MediaSourceKind.xtream)
                    }
                    .accessibilityIdentifier("source-kind")
                }.listRowBackground(MirrorStyle.surface)
                Section {
                    TextField(L10n.tr("Kaynak adı"), text: $name).textInputAutocapitalization(.words)
                        .accessibilityIdentifier("source-name")
                    TextField(kind == .xtream ? "https://server.example" : "https://example.com/playlist.m3u", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(L10n.tr("Kaynak adresi"))
                        .accessibilityIdentifier("source-url")
                    if kind == .xtream {
                        TextField(L10n.tr("Kullanıcı adı"), text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityIdentifier("source-username")
                        SecureField(L10n.tr("Parola"), text: $password)
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityIdentifier("source-password")
                    }
                } footer: { Text(L10n.tr("Mirivo içerik sağlamaz. Erişim hakkına sahip olduğun kaynakları ekleyebilirsin. Adres ve giriş bilgileri cihazındaki Keychain’de saklanır.")) }
                    .listRowBackground(MirrorStyle.surface)
                if let message { Section { Text(message).foregroundStyle(.red) }.listRowBackground(MirrorStyle.surface) }
            }
            .environment(\.defaultMinListRowHeight, MirrorStyle.controlHeight)
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.tr(source == nil ? "Kaynak ekle" : "Kaynak düzenle")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr("Vazgeç"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: { Text(L10n.tr(source == nil ? "Ekle" : "Kaydet")) }
                    .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(!canSave)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(MirrorStyle.background)
            }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
    }
    private func save() {
        do {
            let url = try MediaURL.validate(address)
            let secret = SourceSecret(url: url, username: kind == .xtream ? username : nil, password: kind == .xtream ? password : nil)
            if let source {
                try SourceLibrary.shared.update(source, name: name, kind: kind, secret: secret)
            } else {
                try SourceLibrary.shared.add(name: name, kind: kind, secret: secret, access: PurchaseStore.shared.access)
            }
            dismiss()
        } catch { message = L10n.tr(source == nil ? "Kaynak eklenemedi. Adresi ve giriş bilgilerini kontrol et." : "Kaynak güncellenemedi. Adresi ve giriş bilgilerini kontrol et.") }
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
                    actions: { Button(L10n.tr("Yeniden dene")) { refreshID = UUID() }.buttonStyle(MirivoButtonStyle()) }
            }
            ForEach(filtered) { channel in
                Button {
                    MirrorModel.shared.playMedia(channel)
                    showingPlayer = MirrorModel.shared.selectedMediaChannel != nil
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.title).foregroundStyle(.primary)
                            if !channel.group.isEmpty { Text(channel.group).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(); Image(systemName: "play.circle").foregroundStyle(MirrorStyle.accent)
                    }.frame(minHeight: MirrorStyle.controlHeight).padding(.vertical, 6).contentShape(Rectangle())
                }
                .listRowBackground(MirrorStyle.surface)
            }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
    @ObservedObject private var playback: PlaybackController
    init(model: MirrorModel) {
        self.model = model
        self.playback = model.playback
    }
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var vehicleMode = false
    @State private var showingPro = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if playback.hasActivePlayback {
                    NativeVideoView(player: playback.player).aspectRatio(16 / 9, contentMode: .fit)
                    if playback.state == .loading { ProgressView(L10n.tr("Yayın hazırlanıyor")) }
                }
                Text(model.selectedMediaChannel?.title ?? L10n.tr("Oynatıcı"))
                    .font(.headline).lineLimit(2).padding(.horizontal)
                if let failure = playback.errorMessage ?? model.errorMessage, !playback.hasActivePlayback {
                    ContentUnavailableView {
                        Label(L10n.tr("Yayın tamamlanamadı"), systemImage: "exclamationmark.triangle")
                    } description: { Text(failure) }
                }
                if !playback.hasActivePlayback, model.selectedMediaChannel != nil {
                    Button(L10n.tr("Yeniden dene")) { model.retryMedia() }
                        .buttonStyle(MirivoButtonStyle(prominent: true)).padding(.horizontal, 24)
                }
                if playback.canUseVehicleMode {
                    Button {
                        if purchases.access.fullAccess { vehicleMode = true } else { showingPro = true }
                    } label: { Label(L10n.tr("Araç modu"), systemImage: "car.side") }
                        .buttonStyle(MirivoButtonStyle(prominent: true)).padding(.horizontal, 24)
                }
                if playback.hasActivePlayback {
                    Button(L10n.tr(playback.state == .loading ? "Vazgeç" : "Oynatmayı durdur"), role: .destructive) { model.stopPlayback() }
                        .buttonStyle(MirivoButtonStyle()).padding(24)
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).navigationTitle(L10n.tr("Oynatıcı")).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: playback.canUseVehicleMode) { _, available in
            if !available { vehicleMode = false }
        }
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
                HStack(spacing: 16) {
                    Button { playback.togglePlayPause() } label: {
                        Label(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"), systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { model.stopPlayback(); dismiss() } label: {
                        Label(L10n.tr("Durdur"), systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.font(.title3.weight(.semibold)).frame(maxWidth: .infinity).background(MirrorStyle.surface)
            }.background(.black).foregroundStyle(.white)
        }
        .onAppear { previousIdleState = UIApplication.shared.isIdleTimerDisabled; UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = previousIdleState }
        .statusBarHidden(true)
    }
}
