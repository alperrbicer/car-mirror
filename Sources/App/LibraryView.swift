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
                    .font(.largeTitle.weight(.semibold)).tracking(L10n.appLanguage.allowsLetterSpacing ? -1 : 0)
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
    @State private var loading = true
    @State private var message: String?
    @State private var refreshID = UUID()
    init(source: MediaSource) {
        self.source = source
        let cached = SourceLibrary.shared.cachedChannels(for: source)
        _channels = State(initialValue: cached ?? [])
        _loading = State(initialValue: cached == nil)
    }
    var body: some View {
        Group {
            if loading {
                ProgressView(L10n.tr("Kaynak yükleniyor…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message {
                ContentUnavailableView { Label(message, systemImage: "wifi.exclamationmark") }
                    actions: { Button(L10n.tr("Yeniden dene")) { refreshID = UUID() }.buttonStyle(MirivoButtonStyle()) }
            } else {
                ChannelBrowserView(channels: channels, title: source.name)
            }
        }
        .background(MirrorStyle.background)
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable {
            do { channels = try await SourceLibrary.shared.channels(for: source, reload: true) }
            catch is CancellationError { }
            catch { SourceLibrary.shared.message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
        }
        .task(id: refreshID) {
            // Navigation re-runs this task when returning from a category/player.
            // Keep the existing browser (and its search/scroll state) in place.
            guard channels.isEmpty else { return }
            loading = true; message = nil
            defer { loading = false }
            do { channels = try await SourceLibrary.shared.channels(for: source) }
            catch is CancellationError { }
            catch { message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
        }
    }
}

private struct ChannelBrowserView: View {
    let channels: [MediaChannel]
    let title: String
    var showsCategories = true
    @State private var query = ""
    @State private var playbackMessage: String?
    @State private var showingPlayer = false
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [MediaChannel] {
        searchTerm.isEmpty ? channels : channels.filter {
            $0.title.localizedCaseInsensitiveContains(searchTerm) || $0.group.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    private var categories: [MediaChannelCategory] { MediaChannelCategory.group(channels) }
    var body: some View {
        List {
            if showsCategories && searchTerm.isEmpty && categories.contains(where: { !$0.name.isEmpty }) {
                NavigationLink {
                    ChannelBrowserView(channels: channels, title: L10n.tr("Tüm kanallar"), showsCategories: false)
                } label: {
                    categoryLabel(L10n.tr("Tüm kanallar"), count: channels.count, icon: "list.bullet")
                }.listRowBackground(MirrorStyle.surface)
                ForEach(categories) { category in
                    let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
                    NavigationLink {
                        ChannelBrowserView(channels: category.channels, title: name, showsCategories: false)
                    } label: { categoryLabel(name, count: category.channels.count, icon: "folder") }
                        .listRowBackground(MirrorStyle.surface)
                }
            } else {
                ForEach(filtered) { channel in
                    Button {
                        let model = MirrorModel.shared
                        if !model.playMedia(channel, queue: filtered), model.dailyRemaining == 0 {
                            playbackMessage = model.errorMessage
                            model.errorMessage = nil
                        } else { showingPlayer = model.selectedMediaChannel != nil }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.title).foregroundStyle(.primary)
                                if !channel.group.isEmpty { Text(channel.group).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(); Image(systemName: "play.circle").foregroundStyle(MirrorStyle.accent)
                        }.frame(minHeight: MirrorStyle.controlHeight).padding(.vertical, 6).contentShape(Rectangle())
                    }.listRowBackground(MirrorStyle.surface)
                }
            }
        }
        .overlay {
            if !searchTerm.isEmpty && filtered.isEmpty { ContentUnavailableView.search(text: searchTerm) }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, prompt: L10n.tr("Kanal veya grup ara"))
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: .shared) }
        .safeAreaInset(edge: .bottom) { NowPlayingBar { showingPlayer = true } }
        .alert(BrandIdentity.name, isPresented: Binding(get: { playbackMessage != nil }, set: { if !$0 { playbackMessage = nil } })) {
            Button(L10n.tr("Tamam")) { playbackMessage = nil }
        } message: { Text(playbackMessage ?? "") }
    }
    private func categoryLabel(_ name: String, count: Int, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(MirrorStyle.accent).frame(width: 26)
            Text(name).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }.frame(minHeight: MirrorStyle.controlHeight).padding(.vertical, 6)
    }
}

struct NowPlayingBar: View {
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    let open: () -> Void
    @State private var visible = false
    var body: some View {
        if let title = model.mediaTitle, playback.hasActivePlayback {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Group {
                            if visible && !model.playerScreenVisible {
                                if let engine = playback.compatibility { CompatibilityVideoView(engine: engine, role: .preview) }
                                else { NativeVideoView(player: playback.player, showsControls: false) }
                            } else { Color.black }
                        }.frame(width: 88, height: 50).clipShape(RoundedRectangle(cornerRadius: 9))
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr(playback.state == .playing ? "Şimdi oynatılıyor" : playback.state == .loading ? "Yayın hazırlanıyor" : "Yayın duraklatıldı"))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up")
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("now-playing-open")
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
            }.padding(.horizontal, 18).padding(.vertical, 10)
                .background(MirrorStyle.surface).foregroundStyle(.white)
                .onAppear { visible = true }.onDisappear { visible = false }
        }
    }
}

struct NativeVideoView: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsControls = true
    var playback: PlaybackController?
    var fillsFrame = false
    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsControls
        controller.allowsPictureInPicturePlayback = playback != nil || showsControls
        controller.canStartPictureInPictureAutomaticallyFromInline = playback != nil || showsControls
        controller.delegate = context.coordinator
        controller.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
    }
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        weak var playback: PlaybackController?
        init(playback: PlaybackController?) { self.playback = playback }
        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool { false }
        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            playback?.retainedPiPController = playerViewController
            playback?.retainedPiPDelegate = self
        }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            playback?.retainedPiPController = nil
            playback?.retainedPiPDelegate = nil
        }
        func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) {
            playback?.retainedPiPController = nil
            playback?.retainedPiPDelegate = nil
        }
        func playerViewController(_ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            guard let restore = playback?.onRestorePlayer else { completionHandler(false); return }
            restore(completionHandler)
        }
    }
}

private struct CompatibilityVideoView: UIViewRepresentable {
    let engine: CompatibilityPlayback
    var role: CompatibilityVideoHost.Role = .inline
    var fillsFrame = false
    func makeUIView(context: Context) -> CompatibilityVideoHost {
        let view = CompatibilityVideoHost()
        view.configure(engine: engine, role: role, fillsFrame: fillsFrame)
        return view
    }
    func updateUIView(_ view: CompatibilityVideoHost, context: Context) {
        view.configure(engine: engine, role: role, fillsFrame: fillsFrame)
    }
    static func dismantleUIView(_ view: CompatibilityVideoHost, coordinator: ()) { view.detach() }
}

private struct MediaVideoView: View {
    @ObservedObject var playback: PlaybackController
    var role: CompatibilityVideoHost.Role = .inline
    var fillsFrame = false
    var showsControls = true
    var body: some View {
        if let engine = playback.compatibility {
            VStack(spacing: 10) {
                CompatibilityVideoView(engine: engine, role: role, fillsFrame: fillsFrame)
                if showsControls && role != .fullscreen { HStack {
                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
                    Spacer()
                    Button { engine.pip?.startPictureInPicture() } label: {
                        Image(systemName: "pip.enter").frame(width: 44, height: 44)
                    }.accessibilityLabel("Picture in Picture")
                }.padding(.horizontal, 12) }
            }
        } else {
            NativeVideoView(player: playback.player, showsControls: showsControls, playback: playback, fillsFrame: fillsFrame)
        }
    }
}

/// Shared time and seek controls for the inline and full-screen players.
private struct PlaybackTimelineView: View {
    @ObservedObject var playback: PlaybackController
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var scrubTime: Double?

    private var position: Double { min(max(0, scrubTime ?? playback.currentTime), max(1, playback.duration)) }
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { position }, set: { scrubTime = $0 }),
                   in: 0...max(1, playback.duration), onEditingChanged: { editing in
                onEditingChanged(editing)
                if !editing {
                    if let scrubTime { playback.seek(to: scrubTime) }
                    scrubTime = nil
                }
            })
            .tint(MirrorStyle.accent).disabled(!playback.canSeek)
            .opacity(playback.isLive ? 0 : 1).accessibilityHidden(playback.isLive)
            .accessibilityLabel(L10n.tr("Oynatma konumu"))
            .accessibilityValue(PlaybackTimeDisplay.timestamp(position))
            HStack {
                if playback.isLive {
                    Label {
                        Text(L10n.tr("Canlı"))
                    } icon: {
                        Circle().fill(MirrorStyle.accent).frame(width: 6, height: 6)
                    }
                } else {
                    Text(PlaybackTimeDisplay.timestamp(scrubTime ?? playback.currentTime))
                        .accessibilityLabel(L10n.tr("Geçen süre"))
                        .accessibilityValue(PlaybackTimeDisplay.timestamp(scrubTime ?? playback.currentTime))
                }
                Spacer(minLength: 12)
                Text(playback.duration > 0 ? PlaybackTimeDisplay.timestamp(playback.duration) : "--:--")
                    .opacity(playback.isLive ? 0 : 1).accessibilityHidden(playback.isLive)
                    .accessibilityLabel(L10n.tr("Toplam süre"))
                    .accessibilityValue(playback.duration > 0 ? PlaybackTimeDisplay.timestamp(playback.duration) : "--:--")
            }.font(.caption.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct MediaPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    init(model: MirrorModel) {
        self.model = model
        self.playback = model.playback
    }
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var vehicleMode = false
    @State private var fullscreen = false
    @State private var showingChannels = false
    @State private var showingPro = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if playback.hasActivePlayback {
                    if fullscreen { Color.black.aspectRatio(16 / 9, contentMode: .fit) }
                    else {
                        MediaVideoView(playback: playback).aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                if playback.state == .loading {
                                    ProgressView(L10n.tr("Yayın hazırlanıyor"))
                                        .padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
                Text(model.selectedMediaChannel?.title ?? L10n.tr("Oynatıcı"))
                    .font(.headline).lineLimit(2).padding(.horizontal)
                if let failure = model.mediaErrorMessage, !playback.hasActivePlayback {
                    ContentUnavailableView {
                        Label(L10n.tr("Yayın tamamlanamadı"), systemImage: "exclamationmark.triangle")
                    } description: { Text(failure) }
                }
                if !playback.hasActivePlayback, model.selectedMediaChannel != nil {
                    Button(L10n.tr("Yeniden dene")) { model.retryMedia() }
                        .buttonStyle(MirivoButtonStyle(prominent: true)).padding(.horizontal, 24)
                }
                if playback.hasActivePlayback {
                    VStack(spacing: 20) {
                        PlaybackTimelineView(playback: playback).id(model.selectedMediaChannel?.id)
                        HStack(spacing: 24) {
                            channelStep(-1)
                            Button { playback.togglePlayPause() } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title).frame(width: 72, height: 72)
                                    .background(MirrorStyle.accent, in: Circle()).foregroundStyle(.black)
                            }.accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
                            channelStep(1)
                        }.buttonStyle(.plain)
                        HStack(spacing: 12) {
                            playerAction("Tam ekran", icon: "arrow.up.left.and.arrow.down.right") {
                                vehicleMode = false; fullscreen = true
                            }
                            playerAction("Araç modu", icon: "car.side") {
                                if purchases.access.fullAccess { vehicleMode = true; fullscreen = true }
                                else { showingPro = true }
                            }
                            playerAction("Kanallar", icon: "list.bullet") { showingChannels = true }
                        }
                        if !purchases.verifiedPro {
                            VStack(spacing: 8) {
                                ProgressView(value: model.dailyRemaining, total: DailyViewingBudget.limit).tint(MirrorStyle.accent)
                                Text(String(format: L10n.tr("Bugün kalan: %d dk"), Int(ceil(model.dailyRemaining / 60))))
                                    .font(.caption).foregroundStyle(MirrorStyle.secondary)
                            }
                        }
                        Button(role: .destructive) { model.stopPlayback() } label: {
                            Label(L10n.tr("Oynatmayı durdur"), systemImage: "stop.circle").font(.subheadline)
                                .frame(minHeight: 44)
                        }
                    }.padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(MirrorStyle.background).navigationTitle(L10n.tr("Oynatıcı")).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { model.playerVisibilityChanged(true) }
        .onDisappear { model.playerVisibilityChanged(false) }
        .onChange(of: model.selectedMediaChannel) { _, channel in
            guard channel == nil else { return }
            if fullscreen { fullscreen = false } else { dismiss() }
        }
        .onChange(of: playback.state) { _, state in
            if state == .failed || (state == .idle && model.selectedMediaChannel != nil) { fullscreen = false }
        }
        .fullScreenCover(isPresented: $fullscreen, onDismiss: {
            // Let the full-screen cover finish closing before popping the player.
            if model.selectedMediaChannel == nil { dismiss() }
        }) { VehicleModeView(vehicleMode: vehicleMode, model: model) { fullscreen = false } }
        .sheet(isPresented: $showingChannels) {
            NavigationStack {
                List(model.playbackQueue) { channel in
                    Button {
                        model.playMedia(channel)
                        showingChannels = false
                    } label: {
                        HStack {
                            Text(channel.title)
                            Spacer()
                            if channel.id == model.selectedMediaChannel?.id { Image(systemName: "waveform") }
                        }.frame(minHeight: 44)
                    }.listRowBackground(MirrorStyle.surface)
                }.scrollContentBackground(.hidden).background(MirrorStyle.background)
                    .navigationTitle(L10n.tr("Kanallar"))
                    .toolbar { Button(L10n.tr("Kapat")) { showingChannels = false } }
            }.presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPro) { NavigationStack { ProView() } }
        .alert(BrandIdentity.name, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private func channelStep(_ offset: Int) -> some View {
        Button { model.switchChannel(offset) } label: {
            Image(systemName: offset < 0 ? "backward.end.fill" : "forward.end.fill")
                .font(.title2).frame(width: 56, height: 56)
        }.disabled(model.adjacentChannel(offset) == nil)
            .accessibilityLabel(L10n.tr(offset < 0 ? "Önceki kanal" : "Sonraki kanal"))
    }
    private func playerAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.title3)
                Text(L10n.tr(title)).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity, minHeight: 78)
                .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

}

struct VehicleModeView: View {
    var vehicleMode: Bool = true
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback = MirrorModel.shared.playback
    let close: () -> Void
    @State private var previousIdleState = false
    @State private var fillsFrame = false
    @State private var controlsLocked = false
    @State private var showingChannels = false
    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        // Chrome must never participate in the video's size proposal. In
        // landscape, stacking these rows leaves only a thumbnail-sized image.
        MediaVideoView(playback: playback, role: .fullscreen, fillsFrame: fillsFrame, showsControls: !vehicleMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped().ignoresSafeArea()
            .allowsHitTesting(!controlsLocked).accessibilityHidden(controlsLocked)
            .simultaneousGesture(TapGesture().onEnded { toggleControls() })
            .overlay {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        header
                            .padding(.vertical, 8)
                            .background {
                                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                                    .ignoresSafeArea(edges: .top)
                            }
                            .opacity(controlsVisible || controlsLocked ? 1 : 0)
                            .allowsHitTesting(controlsVisible || controlsLocked)
                            .accessibilityHidden(!controlsVisible && !controlsLocked)
                        Spacer(minLength: 0)
                        playerControls(compact: geometry.size.width > geometry.size.height)
                            .padding(.top, 20).padding(.bottom, 8)
                            .background {
                                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                    .ignoresSafeArea(edges: .bottom)
                            }
                            .opacity(controlsVisible && !controlsLocked ? 1 : 0)
                            .allowsHitTesting(controlsVisible && !controlsLocked)
                            .accessibilityHidden(!controlsVisible || controlsLocked)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .foregroundStyle(.white).buttonStyle(.plain)
            .background(.black)
            .sheet(isPresented: $showingChannels) { VehicleChannelPicker(model: model) }
            .onAppear {
                previousIdleState = UIApplication.shared.isIdleTimerDisabled
                UIApplication.shared.isIdleTimerDisabled = true
                scheduleControlsHide()
            }
            .onDisappear {
                hideControlsTask?.cancel()
                UIApplication.shared.isIdleTimerDisabled = previousIdleState
            }
            .onChange(of: playback.isPlaying) { _, _ in revealControls() }
            .onChange(of: controlsLocked) { _, _ in revealControls() }
            .onChange(of: showingChannels) { _, _ in revealControls() }
            .onChange(of: model.selectedMediaChannel?.id) { _, _ in revealControls() }
            .statusBarHidden(true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr(vehicleMode ? "Araç modu" : "Tam ekran"))
                    .font(.caption.weight(.medium)).foregroundStyle(MirrorStyle.accent)
                Text(model.mediaTitle ?? BrandIdentity.name)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if controlsLocked {
                Button { controlsLocked = false } label: {
                    Label(L10n.tr("Kilidi aç"), systemImage: "lock.open.fill")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 48)
                        .background(MirrorStyle.surface, in: Capsule())
                }.accessibilityIdentifier("unlock-player-controls")
            } else {
                if !vehicleMode, let engine = playback.compatibility {
                    Button { engine.pip?.startPictureInPicture() } label: {
                        Image(systemName: "pip.enter").font(.headline).frame(width: 44, height: 44)
                            .background(.white.opacity(0.1), in: Circle())
                    }.accessibilityLabel("Picture in Picture")
                }
                Button(action: close) {
                    Image(systemName: "chevron.down").font(.headline).frame(width: 44, height: 44)
                        .background(.white.opacity(0.1), in: Circle())
                }.accessibilityLabel(L10n.tr("Kapat"))
            }
        }.padding(.horizontal, 20)
    }

    private func playerControls(compact: Bool) -> some View {
        VStack(spacing: 8) {
            PlaybackTimelineView(playback: playback) { editing in
                isScrubbing = editing
                revealControls()
            }.id(model.selectedMediaChannel?.id)
                .padding(.horizontal, 24).frame(maxWidth: 760)
            if compact {
                HStack(spacing: 12) {
                    modeActions.labelStyle(.iconOnly).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    transportControls(compact: true)
                }.padding(.horizontal, 16).frame(maxWidth: 760)
            } else {
                modeActions
                transportControls(compact: false)
            }
        }
    }

    @ViewBuilder private var modeActions: some View {
        if vehicleMode { vehicleActions } else { viewingActions }
    }

    private func toggleControls() {
        guard !controlsLocked else { return }
        hideControlsTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleControlsHide() }
    }

    private func revealControls() {
        controlsVisible = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        guard controlsVisible, playback.isPlaying, !controlsLocked, !isScrubbing,
              !showingChannels, !UIAccessibility.isVoiceOverRunning else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, !UIAccessibility.isVoiceOverRunning else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private var vehicleActions: some View {
        HStack(spacing: 12) {
            Button { showingChannels = true } label: {
                Label(L10n.tr("Kanallar"), systemImage: "square.grid.2x2")
                    .frame(minWidth: 54, maxWidth: .infinity, minHeight: 60)
                    .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.disabled(model.playbackQueue.isEmpty).accessibilityIdentifier("vehicle-channel-picker")
            Button { controlsLocked = true } label: {
                Label(L10n.tr("Kontrolleri kilitle"), systemImage: "lock.fill")
                    .frame(minWidth: 54, maxWidth: .infinity, minHeight: 60)
                    .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.accessibilityIdentifier("lock-player-controls")
        }.font(.subheadline.weight(.semibold)).padding(.horizontal, 20).frame(maxWidth: 600)
    }

    private var viewingActions: some View {
        HStack(spacing: 16) {
            control("gobackward.10", label: "10 saniye geri") {
                playback.seek(to: playback.currentTime - 10)
            }.disabled(!playback.canSeek).accessibilityIdentifier("skip-backward")
            Button { revealControls(); fillsFrame.toggle() } label: {
                Label(L10n.tr(fillsFrame ? "Görüntüyü sığdır" : "Ekranı doldur"),
                      systemImage: fillsFrame ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44)
                    .background(MirrorStyle.surface, in: Capsule())
            }.accessibilityIdentifier("toggle-video-fill")
            control("goforward.10", label: "10 saniye ileri") {
                playback.seek(to: playback.currentTime + 10)
            }.disabled(!playback.canSeek).accessibilityIdentifier("skip-forward")
        }.padding(.horizontal, 12)
    }

    private func transportControls(compact: Bool) -> some View {
        HStack(spacing: vehicleMode ? 14 : 10) {
            control("backward.end.fill", label: "Önceki kanal") { model.switchChannel(-1) }
                .disabled(model.adjacentChannel(-1) == nil)
            Button { revealControls(); playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: vehicleMode ? 29 : 25, weight: .semibold))
                    .frame(width: compact ? 56 : vehicleMode ? 76 : 58, height: compact ? 56 : vehicleMode ? 76 : 58)
                    .background(MirrorStyle.accent, in: Circle()).foregroundStyle(.black)
            }.accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
            control("forward.end.fill", label: "Sonraki kanal") { model.switchChannel(1) }
                .disabled(model.adjacentChannel(1) == nil)
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 26)
            control("stop.fill", label: "Durdur") { model.stopPlayback() }
        }
        .padding(.horizontal, 16).padding(.vertical, compact ? 6 : 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.1)) }
        .padding(.horizontal, compact ? 0 : 12).padding(.bottom, compact ? 0 : 12)
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button { revealControls(); action() } label: {
            Image(systemName: icon).font(.system(size: vehicleMode ? 23 : 20, weight: .semibold))
                .frame(width: 44, height: vehicleMode ? 60 : 48).contentShape(Rectangle())
        }.accessibilityLabel(L10n.tr(label))
    }
}

private struct VehicleChannelPicker: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        ForEach(model.playbackQueue) { channel in
                            let selected = channel.id == model.selectedMediaChannel?.id
                            Button {
                                model.playMedia(channel)
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: selected ? "waveform" : "play.fill")
                                        .font(.title2).foregroundStyle(MirrorStyle.accent).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(channel.title).font(.headline).lineLimit(2)
                                        if !channel.group.isEmpty {
                                            Text(channel.group).font(.subheadline).foregroundStyle(MirrorStyle.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(18).frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                                    .background(selected ? MirrorStyle.accent.opacity(0.12) : MirrorStyle.surface,
                                                in: RoundedRectangle(cornerRadius: 22))
                                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? MirrorStyle.accent : .clear) }
                            }.buttonStyle(.plain).foregroundStyle(.white)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .id(channel.id)
                        }
                    }.padding(20)
                }.background(MirrorStyle.background)
                    .onAppear {
                        if let id = model.selectedMediaChannel?.id { proxy.scrollTo(id, anchor: .center) }
                    }
            }
            .navigationTitle(L10n.tr("Kanallar")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(L10n.tr("Kapat")) { dismiss() }.frame(minHeight: 44)
            } }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
    }
}
