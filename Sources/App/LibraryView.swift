import SwiftUI
import AVKit
import MediaPlayer
import UniformTypeIdentifiers

enum PlayerVideoDisplayMode: String, CaseIterable, Identifiable {
    case normal
    case fitScreen
    case fillScreen

    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: "Normal"
        case .fitScreen: "Görüntüyü sığdır"
        case .fillScreen: "Ekranı doldur"
        }
    }
    var icon: String {
        switch self {
        case .normal: "arrow.counterclockwise"
        case .fitScreen: "arrow.down.right.and.arrow.up.left"
        case .fillScreen: "arrow.up.left.and.arrow.down.right"
        }
    }
}

private enum PlayerGestureAdjustment: Equatable {
    case volume
    case brightness

    var title: String { L10n.tr(self == .volume ? "Ses düzeyi" : "Parlaklık") }
    var icon: String { self == .volume ? "speaker.wave.2.fill" : "sun.max.fill" }
}

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var purchases = PurchaseStore.shared
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    @State private var adding = false
    @State private var editing: SourceEditDraft?
    @State private var showingPro = false
    @State private var refreshingSources: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr(library.sources.isEmpty ? "Kaynakların burada" : "Kaynaklar"))
                    .font(.largeTitle.weight(.semibold)).tracking(L10n.appLanguage.allowsLetterSpacing ? -1 : 0)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.tr("Bir oynatma listesi, yayın bağlantısı veya IPTV sunucusu ekle."))
                    .font(.subheadline).foregroundStyle(MirrorStyle.secondary).lineSpacing(4)
            }.fixedSize(horizontal: false, vertical: true)
            ContinueWatchingSection()
            OfflineDownloadsSection()
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
                                        Text(L10n.tr(source.kind == .xtream ? "IPTV sunucusu" : source.kind == .stream ? "Yayın bağlantısı" : "Oynatma listesi"))
                                            .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                        SourceExpiryView(source: source)
                                    }
                                    Spacer(minLength: 4)
                                }
                                .padding(.leading, 16).padding(.vertical, 18)
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                if source.kind == .playlist || source.kind == .xtream {
                                    Button(L10n.tr("Bilgileri yenile"), systemImage: "arrow.clockwise") {
                                        guard refreshingSources.insert(source.id).inserted else { return }
                                        Task {
                                            defer { refreshingSources.remove(source.id) }
                                            async let minimumDisplay: Void = Task.sleep(for: .milliseconds(1500))
                                            await library.accounts.refresh(for: source, force: true)
                                            _ = try? await minimumDisplay
                                        }
                                    }.disabled(refreshingSources.contains(source.id))
                                }
                                Button(L10n.tr("Düzenle"), systemImage: "pencil") {
                                    do { editing = SourceEditDraft(source: source, secret: try SourceKeychain.read(source.id)) }
                                    catch { library.message = L10n.tr("Kaynaklar açılamadı. Lütfen yeniden dene.") }
                                }
                                Button(role: .destructive) {
                                    do { try library.delete(source) }
                                    catch { library.message = L10n.tr("Kaynak silinemedi. Yeniden dene.") }
                                } label: {
                                    Label(L10n.tr("Sil"), systemImage: "trash")
                                }
                            } label: {
                                Group {
                                    if refreshingSources.contains(source.id) {
                                        ProgressView().tint(MirrorStyle.accent)
                                            .accessibilityLabel(L10n.tr("Bitiş tarihi alınıyor…"))
                                    } else {
                                        Image(systemName: "ellipsis").font(.body.weight(.semibold))
                                            .foregroundStyle(MirrorStyle.secondary)
                                    }
                                }.frame(width: 48, height: 58).contentShape(Rectangle())
                            }
                            .accessibilityLabel(source.name)
                            .accessibilityValue(refreshingSources.contains(source.id) ? L10n.tr("Bitiş tarihi alınıyor…") : "")
                        }
                        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(MirrorStyle.hairline) }
                        .task(id: source) { await library.accounts.refresh(for: source) }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { Task { await library.accounts.refresh(for: source) } }
                        }
                    }
                }
            }
            Button { add() } label: {
                HStack { Text(L10n.tr("Kaynak ekle")); Spacer(); Image(systemName: "plus") }
            }
            .buttonStyle(MirivoButtonStyle(prominent: true))
            .accessibilityIdentifier("add-source")
        }
        .overlay {
            if !refreshingSources.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().tint(MirrorStyle.accent).controlSize(.large)
                    Text(L10n.tr("Bilgiler yenileniyor…")).font(.subheadline)
                }
                .padding(24).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MirrorStyle.hairline) }
                .shadow(color: .black.opacity(0.3), radius: 16)
                .allowsHitTesting(false).accessibilityElement(children: .contain).accessibilityIdentifier("source-refresh-progress")
            }
        }
        .sheet(isPresented: $adding) { SourceEditorView() }
        .sheet(item: $editing) { draft in SourceEditorView(source: draft.source, secret: draft.secret) }
        .sheet(isPresented: $showingPro) {
            NavigationStack { ProView() }
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

private struct ContinueWatchingSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var history = LastPlaybackStore.shared
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    @State private var showingAll = false
    @State private var showingPlayer = false
    @State private var query = ""
    @State private var message: String?
    private var items: [LastPlaybackRecord] {
        history.entries.filter { entry in
            entry.id != model.activeContinuationID &&
            (entry.sourceID == nil || library.sources.contains { $0.id == entry.sourceID })
        }
    }
    private var filtered: [LastPlaybackRecord] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? items : items.filter { $0.title.localizedStandardContains(search) }
    }
    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    headerLayout {
                        Text(L10n.tr("İzlemeye devam et")).font(.headline).accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        if items.count > 3 {
                            Button(L10n.tr("Tümünü gör")) { query = ""; showingAll = true }
                                .font(.subheadline).foregroundStyle(MirrorStyle.accent)
                                .frame(minHeight: 44).accessibilityIdentifier("continue-watching-all")
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(items.prefix(3))) { entry in
                                ContinueWatchingCard(entry: entry, open: { resume(entry) }, remove: { remove(entry) })
                            }
                        }
                    }.scrollIndicators(.hidden)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("continue-watching-section")
            }
        }
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                List {
                    ForEach(filtered) { entry in
                        Button { resume(entry) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(MirrorStyle.accent)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    ContinueWatchingProgress(entry: entry)
                                }
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowBackground(MirrorStyle.surface)
                            .accessibilityIdentifier("continue-list-open-\(entry.id)")
                            .swipeActions {
                                Button(role: .destructive) { remove(entry) } label: {
                                    Label(L10n.tr("Listeden kaldır"), systemImage: "trash")
                                }
                            }
                    }
                }
                .scrollContentBackground(.hidden).background(MirrorStyle.background)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView(L10n.tr("İçerik bulunamadı"), systemImage: "play.rectangle")
                    }
                }
                .searchable(text: $query, prompt: L10n.tr("Film veya dizi ara"))
                .navigationTitle(L10n.tr("İzlemeye devam et")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.tr("Kapat"), systemImage: "xmark") { showingAll = false }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("close-continue-watching")
                    }
                }
            }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
                .alert(BrandIdentity.name, isPresented: messagePresented(inSheet: true)) {
                    Button(L10n.tr("Tamam"), role: .cancel) { message = nil }
                } message: { Text(message ?? "") }
        }
        .alert(BrandIdentity.name, isPresented: messagePresented(inSheet: false)) {
            Button(L10n.tr("Tamam"), role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }
    private func messagePresented(inSheet: Bool) -> Binding<Bool> {
        Binding(get: { showingAll == inSheet && message != nil }, set: { if !$0 { message = nil } })
    }
    private func resume(_ entry: LastPlaybackRecord) {
        if model.resumePlayback(entry) { showingAll = false; showingPlayer = true }
        else {
            message = model.errorMessage ?? L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
            model.errorMessage = nil
        }
    }
    private func remove(_ entry: LastPlaybackRecord) {
        do { try model.removeContinuation(entry.id) }
        catch { message = L10n.tr("İzleme kaydı kaldırılamadı. Yeniden dene.") }
    }
}

private struct OfflineDownloadsSection: View {
    @ObservedObject private var downloads = OfflineDownloadStore.shared
    var body: some View {
        if !downloads.items.isEmpty {
            NavigationLink { OfflineDownloadsView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(MirrorStyle.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("İndirilenler")).font(.headline).foregroundStyle(.white)
                        Text(downloads.items.count.formatted()).font(.caption.monospacedDigit())
                            .foregroundStyle(MirrorStyle.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
                }
                .padding(16).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
            }.buttonStyle(.plain).accessibilityIdentifier("offline-downloads-open")
        }
    }
}

private struct OfflineDownloadsView: View {
    @ObservedObject private var downloads = OfflineDownloadStore.shared
    @ObservedObject private var model = MirrorModel.shared
    @State private var showingPlayer = false
    var body: some View {
        List {
            Text(L10n.tr("Yalnızca sağlayıcının indirmeye izin verdiği içerikleri indir. DRM korumalı yayınlar desteklenmez."))
                .font(.footnote).foregroundStyle(MirrorStyle.secondary).listRowBackground(Color.clear)
            ForEach(downloads.items) { item in
                HStack(spacing: 12) {
                    if let channel = item.channel {
                        Button {
                            if model.playMedia(channel, sourceID: nil) { showingPlayer = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.title).font(.headline).foregroundStyle(.primary)
                                if item.state == .finished {
                                    Label(L10n.tr("Çevrimdışı izlemeye hazır"), systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(MirrorStyle.accent)
                                } else { progressLabel(item) }
                            }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.title).font(.headline)
                            if item.state == .failed { Text(L10n.tr("İndirme başarısız")).font(.caption).foregroundStyle(.orange) }
                            else { progressLabel(item) }
                        }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }
                    if item.state == .downloading || item.state == .preparing {
                        Button { downloads.cancel(item) } label: { Image(systemName: "xmark.circle").font(.title3) }
                            .buttonStyle(.plain).foregroundStyle(MirrorStyle.secondary)
                            .accessibilityLabel(L10n.tr("İndirmeyi iptal et"))
                    }
                }
                .listRowBackground(MirrorStyle.surface)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { downloads.delete(item) } label: { Label(L10n.tr("Sil"), systemImage: "trash") }
                }
            }
        }
        .overlay {
            if downloads.items.isEmpty {
                ContentUnavailableView(L10n.tr("Henüz indirilen içerik yok"), systemImage: "arrow.down.circle")
            }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(L10n.tr("İndirilenler")).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        .safeAreaInset(edge: .bottom) { NowPlayingBar { showingPlayer = true } }
        .alert(BrandIdentity.name, isPresented: Binding(get: { downloads.message != nil }, set: { if !$0 { downloads.message = nil } })) {
            Button(L10n.tr("Tamam")) { downloads.message = nil }
        } message: { Text(downloads.message ?? "") }
    }
    @ViewBuilder private func progressLabel(_ item: OfflineDownload) -> some View {
        if item.state == .preparing { Label(L10n.tr("İçerik kontrol ediliyor…"), systemImage: "ellipsis.circle").font(.caption).foregroundStyle(MirrorStyle.secondary) }
        else {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("İndiriliyor")).font(.caption).foregroundStyle(MirrorStyle.secondary)
                if item.taskIdentifier == nil { ProgressView().tint(MirrorStyle.accent) }
                else { ProgressView(value: item.progress).tint(MirrorStyle.accent) }
            }
        }
    }
}

private struct ContinueWatchingCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: LastPlaybackRecord
    let open: () -> Void
    let remove: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(MirrorStyle.accent)
                    Spacer(minLength: 44)
                }.frame(height: 32)
                Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                ContinueWatchingProgress(entry: entry)
            }.padding(16).frame(width: dynamicTypeSize.isAccessibilitySize ? 300 : 240)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("continue-watching-open-\(entry.id)")
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button(action: remove) { Label(L10n.tr("Listeden kaldır"), systemImage: "xmark.circle") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(MirrorStyle.secondary).frame(width: 44, height: 44)
                }.padding(6).accessibilityLabel(entry.title)
                    .accessibilityIdentifier("continue-watching-menu-\(entry.id)")
            }
    }
}

private struct ContinueWatchingProgress: View {
    let entry: LastPlaybackRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = entry.progress { ProgressView(value: progress).tint(MirrorStyle.accent) }
            Text(PlaybackTimeDisplay.timestamp(entry.resumePosition) +
                 (entry.duration > 0 ? " / " + PlaybackTimeDisplay.timestamp(entry.duration) : ""))
                .font(.caption.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.layoutDirection, .leftToRight)
        }
    }
}

private struct SourceExpiryView: View {
    let source: MediaSource
    @ObservedObject private var accounts = SourceLibrary.shared.accounts

    var body: some View {
        let state = accounts.state(for: source)
        Group {
            switch state {
            case .information(let snapshot, _):
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Label(expiryText(snapshot.info, now: context.date), systemImage: "calendar")
                        .foregroundStyle(snapshot.info.isExpired(at: context.date) ? Color.orange : MirrorStyle.secondary)
                        .accessibilityIdentifier("source-expiry")
                }
            case .failed:
                Text(L10n.tr("Bitiş tarihi alınamadı")).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityIdentifier("source-expiry")
            case .loading:
                Text(L10n.tr("Bitiş tarihi alınıyor…")).foregroundStyle(MirrorStyle.secondary)
            case .unsupported, .none:
                EmptyView()
            }
        }
        .font(.caption).fixedSize(horizontal: false, vertical: true)
    }

    private func expiryText(_ info: IPTVAccountInfo, now: Date) -> String {
        if let date = info.expiresAt {
            return String(format: L10n.tr(info.isExpired(at: now) ? "IPTV süresi doldu: %@" : "IPTV bitişi: %@"), dateText(date))
        }
        return L10n.tr(info.isExpired(at: now) ? "IPTV süresi doldu" : "Bitiş tarihi paylaşılmıyor")
    }
    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.language)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct SourceEditDraft: Identifiable {
    let source: MediaSource
    let secret: SourceSecret
    var id: UUID { source.id }
}

private struct SourceEditorView: View {
    private let source: MediaSource?
    private let originalSecret: SourceSecret?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var kind: MediaSourceKind = .playlist
    @State private var message: String?
    @State private var selectingFile = false
    @State private var selectedFile: URL?
    init(source: MediaSource? = nil, secret: SourceSecret? = nil) {
        self.source = source
        self.originalSecret = secret
        _name = State(initialValue: source?.name ?? "")
        _kind = State(initialValue: source?.kind ?? .playlist)
        _address = State(initialValue: secret?.url.absoluteString ?? "")
        _username = State(initialValue: secret?.username ?? "")
        _password = State(initialValue: secret?.password ?? "")
    }
    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind == .playlistFile { return selectedFile != nil || (source?.kind == .playlistFile && originalSecret != nil) }
        guard let url = try? MediaURL.validate(address) else { return false }
        return kind != .xtream || (try? XtreamEndpoint.playlist(secret: SourceSecret(url: url, username: username, password: password))) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.tr("Kaynak türü"), selection: $kind) {
                        Text(L10n.tr("M3U oynatma listesi")).tag(MediaSourceKind.playlist)
                        Text(L10n.tr("Yayın bağlantısı")).tag(MediaSourceKind.stream)
                        Text(L10n.tr("Xtream Codes")).tag(MediaSourceKind.xtream)
                        Text(L10n.tr("Dosyadan oynatma listesi")).tag(MediaSourceKind.playlistFile)
                    }
                    .accessibilityIdentifier("source-kind")
                }.listRowBackground(MirrorStyle.surface)
                Section {
                    TextField(L10n.tr("Kaynak adı"), text: $name).textInputAutocapitalization(.words)
                        .accessibilityIdentifier("source-name")
                    if kind == .playlistFile {
                        Button { selectingFile = true } label: {
                            Label(selectedFile?.lastPathComponent ?? L10n.tr("Dosya seç"), systemImage: "doc.badge.plus")
                                .lineLimit(2)
                        }.accessibilityIdentifier("source-file")
                    } else {
                    TextField(kind == .xtream ? "https://server.example" : kind == .stream ? "https://example.com/video.mp4" : "https://example.com/playlist.m3u", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(L10n.tr("Kaynak adresi"))
                        .accessibilityIdentifier("source-url")
                    }
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
            .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.m3uPlaylist], allowsMultipleSelection: false) { result in
                do {
                    selectedFile = try result.get().first
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = selectedFile?.deletingPathExtension().lastPathComponent ?? ""
                    }
                    message = nil
                } catch { message = L10n.tr("Oynatma listesi dosyası açılamadı. M3U veya M3U8 dosyası seç.") }
            }
    }
    private func save() {
        do {
            if kind == .playlistFile {
                if let selectedFile {
                    try SourceLibrary.shared.importPlaylist(selectedFile, name: name, replacing: source, access: PurchaseStore.shared.access)
                } else if let source, let originalSecret, source.kind == .playlistFile {
                    try SourceLibrary.shared.update(source, name: name, kind: kind, secret: originalSecret)
                } else { throw LibraryError.invalidURL }
                dismiss()
                return
            }
            let url = try MediaURL.validate(address)
            let secret = SourceSecret(url: url, username: kind == .xtream ? username : nil, password: kind == .xtream ? password : nil)
            if let source {
                try SourceLibrary.shared.update(source, name: name, kind: kind, secret: secret)
            } else {
                try SourceLibrary.shared.add(name: name, kind: kind, secret: secret, access: PurchaseStore.shared.access)
            }
            dismiss()
        } catch {
            message = kind == .playlistFile ? L10n.tr("Oynatma listesi dosyası açılamadı. M3U veya M3U8 dosyası seç.") : L10n.tr(source == nil ? "Kaynak eklenemedi. Adresi ve giriş bilgilerini kontrol et." : "Kaynak güncellenemedi. Adresi ve giriş bilgilerini kontrol et.")
        }
    }
}

private struct ChannelListView: View {
    let source: MediaSource
    @Environment(\.scenePhase) private var scenePhase
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
                ChannelBrowserView(channels: channels, title: source.name, sourceID: source.id,
                                   playlistChannels: channels)
            }
        }
        .background(MirrorStyle.background)
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .task(id: source) { await SourceLibrary.shared.accounts.refresh(for: source) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SourceLibrary.shared.accounts.refresh(for: source) } }
        }
        .toolbar(.visible, for: .navigationBar)
        .refreshable {
            async let accountRefresh: () = SourceLibrary.shared.accounts.refresh(for: source, force: true)
            do { channels = try await SourceLibrary.shared.channels(for: source, reload: true) }
            catch is CancellationError { }
            catch { SourceLibrary.shared.message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
            await accountRefresh
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
    @ObservedObject private var downloads = OfflineDownloadStore.shared
    let channels: [MediaChannel]
    let title: String
    var sourceID: UUID?
    var showsCategories = true
    var playlistChannels: [MediaChannel]?
    var onSelectChannel: ((MediaChannel) -> Void)?
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
                    ChannelBrowserView(channels: channels, title: L10n.tr("Tüm kanallar"), sourceID: sourceID,
                                           showsCategories: false, playlistChannels: playlistChannels ?? channels,
                                           onSelectChannel: onSelectChannel)
                } label: {
                    categoryLabel(L10n.tr("Tüm kanallar"), count: channels.count, icon: "list.bullet")
                }.listRowBackground(MirrorStyle.surface)
                ForEach(categories) { category in
                    let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
                    NavigationLink {
                        ChannelBrowserView(channels: category.channels, title: name, sourceID: sourceID,
                                           showsCategories: false, playlistChannels: playlistChannels ?? channels,
                                           onSelectChannel: onSelectChannel)
                    } label: { categoryLabel(name, count: category.channels.count, icon: "folder") }
                        .listRowBackground(MirrorStyle.surface)
                }
            } else {
                ForEach(filtered) { channel in
                    HStack(spacing: 12) {
                        Button {
                            if let onSelectChannel {
                                onSelectChannel(channel)
                            } else {
                                let model = MirrorModel.shared
                                if !model.playMedia(channel, queue: playlistChannels ?? channels, sourceID: sourceID), model.dailyRemaining == 0 {
                                    playbackMessage = model.errorMessage
                                    model.errorMessage = nil
                                } else { showingPlayer = model.selectedMediaChannel != nil }
                            }
                        } label: {
                            HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.title).foregroundStyle(.primary)
                                if !channel.group.isEmpty { Text(channel.group).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 8); Image(systemName: "play.circle").foregroundStyle(MirrorStyle.accent)
                            }.frame(maxWidth: .infinity, minHeight: MirrorStyle.controlHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if ["m3u8", "mp4", "m4v", "mov"].contains(channel.url.pathExtension.lowercased()) {
                            downloadControl(for: channel)
                        }
                    }.padding(.vertical, 5).listRowBackground(MirrorStyle.surface)
                }
            }
        }
        .overlay {
            if !searchTerm.isEmpty && filtered.isEmpty { ContentUnavailableView.search(text: searchTerm) }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TVRouteStatusButton(model: .shared) }
        }
        .searchable(text: $query, prompt: L10n.tr("Kanal veya grup ara"))
        .navigationDestination(isPresented: $showingPlayer) {
            if onSelectChannel == nil { MediaPlayerScreen(model: .shared) }
        }
        .safeAreaInset(edge: .bottom) {
            if onSelectChannel == nil { NowPlayingBar { showingPlayer = true } }
        }
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
    @ViewBuilder private func downloadControl(for channel: MediaChannel) -> some View {
        if let item = downloads.items.first(where: { $0.assetKey == OfflineDownloadStore.assetKey(for: channel.url) }) {
            if item.state == .finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MirrorStyle.accent)
                    .frame(width: 44, height: 44).accessibilityLabel(L10n.tr("İndirildi"))
            } else if item.state == .preparing || item.state == .downloading {
                Button { downloads.cancel(item) } label: {
                    if item.state == .preparing { ProgressView().tint(MirrorStyle.accent) }
                    else if item.taskIdentifier == nil { ProgressView().tint(MirrorStyle.accent) }
                    else { ProgressView(value: item.progress).progressViewStyle(.circular).tint(MirrorStyle.accent) }
                }.frame(width: 44, height: 44).buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("İndirmeyi iptal et"))
            } else {
                Button { Task { await downloads.download(channel, sourceID: sourceID) } } label: {
                    Image(systemName: "arrow.down.circle").foregroundStyle(MirrorStyle.accent).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Yeniden indir"))
            }
        } else {
            Button { Task { await downloads.download(channel, sourceID: sourceID) } } label: {
                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(MirrorStyle.accent).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(L10n.tr("İndir"))
                .accessibilityIdentifier("download-" + OfflineDownloadStore.assetKey(for: channel.url))
        }
    }
}

struct NowPlayingBar: View {
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    @ObservedObject private var history = LastPlaybackStore.shared
    var hidesSavedProgress = false
    let open: () -> Void
    @State private var visible = false
    var body: some View {
        if let title = model.mediaTitle, playback.hasActivePlayback, !model.playerScreenVisible {
            HStack(spacing: 12) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Group {
                            if playback.tvDevice != nil || model.externalScreenCount > 0 || playback.externalPlaybackActive {
                                Image(systemName: "tv.fill").foregroundStyle(MirrorStyle.accent)
                            } else if visible && !model.playerScreenVisible {
                                if let engine = playback.compatibility { CompatibilityVideoView(engine: engine, role: .preview) }
                                else { NativeVideoView(player: playback.player, playback: playback) }
                            } else { Color.black }
                        }.frame(width: 88, height: 50).clipped()
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
        } else if let last = history.record, !last.isFinished, (!hidesSavedProgress || !last.isInProgress),
                  !playback.hasActivePlayback, !model.playerScreenVisible, !model.broadcasting {
            Button {
                if model.resumeLastPlayback() { open() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill").font(.system(size: 34))
                        .foregroundStyle(MirrorStyle.accent).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("İzlemeye devam et")).font(.caption).foregroundStyle(MirrorStyle.secondary)
                        Text(last.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !last.isLive, last.resumePosition > 0 {
                            Text(PlaybackTimeDisplay.timestamp(last.resumePosition))
                                .font(.caption.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                }.padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.white).background(MirrorStyle.surface)
                .accessibilityIdentifier("last-watched-open")
        }
    }
}

/// Mirivo owns the chrome; AVKit only owns the video layer and PiP lifecycle.
struct NativeVideoView: UIViewControllerRepresentable {
    let player: AVPlayer
    var playback: PlaybackController?
    var displayMode: PlayerVideoDisplayMode = .normal
    var primary = true
    func makeUIViewController(context: Context) -> NativeVideoController {
        NativeVideoController(player: player, playback: playback, primary: primary, displayMode: displayMode)
    }
    func updateUIViewController(_ controller: NativeVideoController, context: Context) {
        if controller.videoLayer.player !== player { controller.videoLayer.player = player }
        controller.displayMode = displayMode
        let gravity: AVLayerVideoGravity = displayMode == .fitScreen ? .resizeAspectFill :
            (displayMode == .fillScreen ? .resize : .resizeAspect)
        if controller.videoLayer.videoGravity != gravity { controller.videoLayer.videoGravity = gravity }
        controller.view.setNeedsLayout()
        controller.setPrimary(primary)
    }
}

/// AVKit's source layer and its UIView must describe the same picture rectangle.
/// Keep letterboxing in the outer host, outside this fitted backing layer.
@MainActor
private final class NativeVideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor
final class NativeVideoController: UIViewController, @preconcurrency AVPictureInPictureControllerDelegate {
    private let videoSurface = NativeVideoSurface()
    var videoLayer: AVPlayerLayer { videoSurface.videoLayer }
    // Include the owned controller wrapper as AVKit may animate clipping on
    // its parent surface while transitioning back from PiP.
    private lazy var videoClipping = PlayerVideoClipping(root: view.layer)
    private(set) var pip: AVPictureInPictureController?
    private(set) var startingPiP = false
    private weak var playback: PlaybackController?
    var displayMode: PlayerVideoDisplayMode = .normal
    private var possibleObservation: NSKeyValueObservation?
    private var pipPlaybackID: UUID?
    private var stoppingRetention: NativeVideoController?
    var stoppingForPlaybackReplacement: Bool { stoppingRetention != nil }
    init(player: AVPlayer, playback: PlaybackController?, primary: Bool,
         displayMode: PlayerVideoDisplayMode = .normal) {
        self.playback = playback
        self.displayMode = displayMode
        super.init(nibName: nil, bundle: nil)
        videoLayer.player = player
        if AVPictureInPictureController.isPictureInPictureSupported(), playback != nil {
            pip = AVPictureInPictureController(playerLayer: videoLayer)
            pip?.delegate = self
            possibleObservation = pip?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.playback?.startPendingPictureInPicture() }
            }
        }
        setPrimary(primary)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let surface = UIView()
        surface.backgroundColor = .black
        surface.clipsToBounds = true
        surface.addSubview(videoSurface)
        view = surface
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = PlayerVideoGeometry.frame(size: videoLayer.player?.currentItem?.presentationSize ?? .zero,
            in: view.bounds, mode: displayMode)
        if videoSurface.frame != frame { videoSurface.frame = frame }
        videoClipping.repairIfRestored()
        CATransaction.commit()
    }
    func setPrimary(_ primary: Bool) {
        let automatic = primary && !stoppingForPlaybackReplacement
        if pip?.canStartPictureInPictureAutomaticallyFromInline != automatic {
            pip?.canStartPictureInPictureAutomaticallyFromInline = automatic
        }
        if primary, let pip { playback?.nativePiP = pip }
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard !stoppingForPlaybackReplacement, let playback, playback.hasActivePlayback, playback.compatibility == nil,
              playback.nativePiP === controller else { controller.stopPictureInPicture(); return }
        pipPlaybackID = playback.playbackID
        prepareForPictureInPicture()
        startingPiP = true
        playback.retainedPiPController = self
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        startingPiP = false
        if ownsPlayback(controller) {
            playback?.pictureInPictureStarted()
        } else { controller.stopPictureInPicture() }
    }
    func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        #if DEBUG
        PiPReturnTrace.begin(videoLayer, label: "native")
        #endif
        if ownsPlayback(controller) {
            playback?.pictureInPictureWillStop()
        }
        layoutVideoForPictureInPictureReturn()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        #if DEBUG
        PiPReturnTrace.mark("didStop")
        #endif
        startingPiP = false
        restoreVideoClipping()
        if ownsPlayback(controller) {
            if playback?.retainedPiPController === self { playback?.retainedPiPController = nil }
            playback?.pictureInPictureStopped()
        }
        pipPlaybackID = nil
        stoppingRetention = nil
        if playback?.nativePiP === controller { setPrimary(true); playback?.startPendingPictureInPicture() }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        startingPiP = false
        restoreVideoClipping()
        if ownsPlayback(controller) {
            if playback?.retainedPiPController === self { playback?.retainedPiPController = nil }
            playback?.pictureInPictureStopped()
        }
        pipPlaybackID = nil
        stoppingRetention = nil
        if playback?.nativePiP === controller { setPrimary(true) }
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard let playback, ownsPlayback(controller) else {
            completionHandler(false); return
        }
        playback.restoreUserInterfaceForPictureInPictureStop(completion: completionHandler)
    }
    private func ownsPlayback(_ controller: AVPictureInPictureController) -> Bool {
        guard let playback, pipPlaybackID == playback.playbackID else { return false }
        return playback.retainedPiPController === self || playback.nativePiP === controller
    }
    func preparePictureInPictureRequest() {
        pipPlaybackID = playback?.playbackID
        startingPiP = true
        playback?.retainedPiPController = self
    }
    func stopForPlaybackReplacement() {
        // AVKit finishes asynchronously; keep its source/delegate alive without
        // leaving the old source registered on the new playback session.
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        if pip != nil, startingPiP || pip?.isPictureInPictureActive == true { stoppingRetention = self }
        pip?.stopPictureInPicture()
    }
    func prepareForPictureInPicture() { videoClipping.suspend() }
    func preparePictureInPictureReturn(completion: @escaping (Bool) -> Void) {
        PlayerVideoReturnLayout.prepare(view, sourceLayer: videoLayer, completion: completion)
    }
    func layoutVideoForPictureInPictureReturn() {
        view.window?.layoutIfNeeded()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    func restoreVideoClipping() {
        videoClipping.restore()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
}

struct CompatibilityVideoView: UIViewRepresentable {
    let engine: CompatibilityPlayback
    var role: CompatibilityVideoHost.Role = .inline
    var displayMode: PlayerVideoDisplayMode = .normal
    func makeUIView(context: Context) -> CompatibilityVideoHost {
        let view = CompatibilityVideoHost()
        view.configure(engine: engine, role: role, displayMode: displayMode)
        return view
    }
    func updateUIView(_ view: CompatibilityVideoHost, context: Context) {
        view.configure(engine: engine, role: role, displayMode: displayMode)
    }
    static func dismantleUIView(_ view: CompatibilityVideoHost, coordinator: ()) { view.detach() }
}

struct MediaVideoView: View {
    @ObservedObject var playback: PlaybackController
    var role: CompatibilityVideoHost.Role = .inline
    var displayMode: PlayerVideoDisplayMode = .normal
    var showsControls = false
    var body: some View {
        if playback.tvName != nil || (playback.externalDisplayConnected && role != .external) {
            VStack(spacing: 12) {
                Image(systemName: "tv.fill").font(.largeTitle).foregroundStyle(MirrorStyle.accent)
                Text(playback.tvName ?? L10n.tr("TV bağlantısı")).font(.headline)
                Text(L10n.tr(playback.state == .loading ? "Görüntü bağlanıyor" : playback.isPlaying ? "TV’de oynatılıyor" : "Yayın duraklatıldı"))
                    .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        } else if let engine = playback.compatibility {
            CompatibilityVideoView(engine: engine, role: role, displayMode: displayMode)
                .overlay(alignment: .bottomTrailing) {
                    if showsControls && role != .fullscreen && role != .external {
                        Button { playback.startPictureInPicture() } label: {
                            Image(systemName: "pip.enter").font(.headline)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay { Circle().strokeBorder(.white.opacity(0.16)) }
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .accessibilityLabel("Picture in Picture")
                            .padding(12)
                    }
                }
        } else {
            NativeVideoView(player: playback.player, playback: playback, displayMode: displayMode, primary: role != .external)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @ObservedObject private var purchases = PurchaseStore.shared
    @State private var largeControls = false
    @State private var fullscreen = false
    @AppStorage("player.videoDisplayMode") private var videoDisplayMode = PlayerVideoDisplayMode.normal
    @State private var portraitRequested = false
    @State private var landscapeLayout = false
    @State private var orientationTransitionTask: Task<Void, Never>?
    init(model: MirrorModel) { self.model = model; playback = model.playback }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: fullscreen ? 0 : 20) {
                    if playback.hasActivePlayback {
                        // Keep this surface mounted in both sizes. A cover used to
                        // remove it and mount another decoder surface during the fade.
                        ZStack {
                            if model.selectedMediaChannel?.isAudio == true {
                                ZStack {
                                    MirrorStyle.surface
                                    Image(systemName: "waveform").font(.system(size: 54, weight: .light))
                                        .foregroundStyle(MirrorStyle.accent)
                                }
                            } else {
                                MediaVideoView(playback: playback, role: .inline, displayMode: videoDisplayMode)
                            }
                            PlayerChrome(model: model, fullscreen: $fullscreen, largeControls: $largeControls,
                                         displayMode: $videoDisplayMode, changeFullscreen: setFullscreen,
                                         exitToPortrait: exitFullscreenToPortrait)
                        }
                        .frame(height: fullscreen ? geometry.size.height : max(0, min(geometry.size.width - 40, 720)) * 9 / 16)
                        .background(.black)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("player-video")
                        // A fixed rectangular source avoids animating a second
                        // corner mask while AVKit animates its own PiP window.
                        .clipped()
                        .padding(.horizontal, fullscreen ? 0 : 20)
                    }
                    if !fullscreen { playerDetails }
                }
                .padding(.top, fullscreen ? 0 : 20).padding(.bottom, fullscreen ? 0 : 24)
                .frame(maxWidth: fullscreen ? .infinity : 760).frame(maxWidth: .infinity)
            }
            .scrollDisabled(fullscreen)
            .onAppear {
                landscapeLayout = geometry.size.width > geometry.size.height
                if landscapeLayout && playback.hasActivePlayback { setFullscreen(true) }
            }
            .onChange(of: geometry.size) { _, size in
                scheduleOrientationAdaptation(for: size)
            }
            .onDisappear { orientationTransitionTask?.cancel() }
        }
        .ignoresSafeArea(fullscreen ? .all : [])
        .background(fullscreen ? Color.black : MirrorStyle.background)
        .navigationTitle(model.selectedMediaChannel?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(fullscreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(fullscreen ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(fullscreen)
        .toolbar {
            if model.presentingPlayer && !fullscreen {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel(L10n.tr("Kapat"))
                }
            }
        }
        .onAppear {
            PlayerOrientationPolicy.update(playerVisible: true,
                allowsLandscape: playback.tvName == nil && !playback.externalDisplayConnected && !playback.externalPlaybackActive)
            model.playerVisibilityChanged(true)
        }
        .onDisappear {
            PlayerOrientationPolicy.update(playerVisible: false, allowsLandscape: false)
            model.playerVisibilityChanged(false)
        }
        .onChange(of: playback.tvDevice != nil) { _, connected in
            updateOrientationPolicy()
            if connected { setFullscreen(false) }
        }
        .onChange(of: playback.externalDisplayConnected) { _, _ in
            updateOrientationPolicy()
            if playback.externalDisplayConnected { setFullscreen(false) }
        }
        .onChange(of: playback.externalPlaybackActive) { _, _ in
            updateOrientationPolicy()
            if playback.externalPlaybackActive { setFullscreen(false) }
        }
        .onChange(of: model.selectedMediaChannel) { _, channel in
            if channel == nil { setFullscreen(false); dismiss() }
        }
        .onChange(of: playback.state) { _, state in
            if state == .failed || state == .idle { setFullscreen(false) }
        }
        .onChange(of: playback.hasActivePlayback) { _, active in
            if active && landscapeLayout { setFullscreen(true) }
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var playerDetails: some View {
        VStack(spacing: 20) {
            if let failure = model.mediaErrorMessage, !playback.hasActivePlayback {
                ContentUnavailableView {
                    Label(L10n.tr("Yayın tamamlanamadı"), systemImage: "exclamationmark.triangle")
                } description: { Text(failure) }
            }
            if !playback.hasActivePlayback, model.selectedMediaChannel != nil {
                Button(L10n.tr("Yeniden dene")) { model.retryMedia() }.buttonStyle(MirivoButtonStyle(prominent: true))
            }
            if playback.hasActivePlayback {
                VStack(spacing: 20) {
                    PlaybackTimelineView(playback: playback).id(model.selectedMediaChannel?.id)
                    TVConnectionButton(model: model)
                    if playback.tvName != nil && model.selectedMediaChannel?.url.isFileURL == true {
                        Label(L10n.tr("TV’ye bu iPhone’dan aktarılıyor. Mirivo’yu açık tut."), systemImage: "iphone.radiowaves.left.and.right")
                            .font(.footnote).foregroundStyle(MirrorStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !purchases.access.fullAccess {
                        VStack(spacing: 8) {
                            ProgressView(value: model.dailyRemaining, total: DailyViewingBudget.limit).tint(MirrorStyle.accent)
                            Text(String(format: L10n.tr("Bugün kalan: %d dk"), Int(ceil(model.dailyRemaining / 60))))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                        }
                    }
                    Button(role: .destructive) { model.stopPlayback() } label: {
                        Label(L10n.tr("Oynatmayı durdur"), systemImage: "stop.circle").font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            }
        }.padding(.horizontal, 20)
    }
    private func setFullscreen(_ value: Bool) {
        guard !value || fullscreenAllowed else { return }
        if value {
            portraitRequested = false
            PlayerOrientationPolicy.update(playerVisible: true, allowsLandscape: fullscreenAllowed)
        } else {
            portraitRequested = true
            PlayerOrientationPolicy.update(playerVisible: true, allowsLandscape: false)
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { fullscreen = value }
    }

    private func exitFullscreenToPortrait() { setFullscreen(false) }

    private var fullscreenAllowed: Bool {
        playback.tvName == nil && !playback.externalDisplayConnected && !playback.externalPlaybackActive
    }

    private func updateOrientationPolicy() {
        PlayerOrientationPolicy.update(playerVisible: true, allowsLandscape: fullscreenAllowed && !portraitRequested)
    }

    private func scheduleOrientationAdaptation(for size: CGSize) {
        orientationTransitionTask?.cancel()
        orientationTransitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return }
            let isLandscape = size.width > size.height
            guard isLandscape != landscapeLayout else { return }
            landscapeLayout = isLandscape
            guard !(isLandscape && portraitRequested) else { return }
            // Landscape rotation enters fullscreen; portrait rotation keeps
            // the current mode so portrait fullscreen remains available.
            if isLandscape && playback.hasActivePlayback && fullscreenAllowed { setFullscreen(true) }
        }
    }
}

/// Standalone host used by external previews and rotation regression tests.
struct FullscreenPlayerView: View {
    var largeControls: Bool = true
    @ObservedObject var model: MirrorModel
    let close: () -> Void
    @AppStorage("player.videoDisplayMode") private var videoDisplayMode = PlayerVideoDisplayMode.normal
    var body: some View {
        MediaVideoView(playback: model.playback, role: .fullscreen, displayMode: videoDisplayMode)
            .overlay {
                PlayerChrome(model: model, fullscreen: .constant(true), largeControls: .constant(largeControls),
                             displayMode: $videoDisplayMode, changeFullscreen: { if !$0 { close() } },
                             exitToPortrait: close)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).ignoresSafeArea().statusBarHidden(true)
    }
}

private struct PlayerChrome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("player.edgeGestureIntroShown") private var edgeGestureIntroShown = false
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @Binding var fullscreen: Bool
    @Binding var largeControls: Bool
    @Binding var displayMode: PlayerVideoDisplayMode
    let changeFullscreen: (Bool) -> Void
    let exitToPortrait: () -> Void
    @State private var controlsVisible = true
    @State private var controlsLocked = false
    @State private var showingChannels = false
    @State private var showingMediaChoices = false
    @State private var showingOptions = false
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?
    @State private var awakeLease: UUID?
    @State private var screenInsets = EdgeInsets()
    @State private var seekFeedback: Int?
    @State private var seekFeedbackPulse = 0
    @State private var feedbackTask: Task<Void, Never>?
    @State private var optionsTask: Task<Void, Never>?
    @State private var showingEdgeGestureIntro = false
    @State private var gestureAdjustment: PlayerGestureAdjustment?
    @State private var gestureAdjustmentValue: CGFloat = 0
    @State private var adjustmentHideTask: Task<Void, Never>?

    init(model: MirrorModel, fullscreen: Binding<Bool>, largeControls: Binding<Bool>, displayMode: Binding<PlayerVideoDisplayMode>,
         changeFullscreen: @escaping (Bool) -> Void, exitToPortrait: @escaping () -> Void) {
        self.model = model; playback = model.playback
        _fullscreen = fullscreen; _largeControls = largeControls; _displayMode = displayMode
        self.changeFullscreen = changeFullscreen
        self.exitToPortrait = exitToPortrait
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerGestureSurface(locked: controlsLocked || showingEdgeGestureIntro,
                                     fullscreen: fullscreen,
                                     singleTap: toggleControls, doubleTap: skip,
                                     swipeDown: exitToPortrait,
                                     adjustBrightness: adjustBrightness,
                                     adjustVolume: { value in showGestureAdjustment(.volume, value: value) },
                                     pinchEnded: handlePinch,
                                     safeAreaChanged: { if screenInsets != $0 { screenInsets = $0 } })
                    .accessibilityHidden(true)
                if controlsVisible && !controlsLocked {
                    LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    if playback.state != .loading { transportControls }
                }
                if let seekFeedback {
                    let transportWidth: CGFloat = fullscreen ? (largeControls ? 224 : 204) : 180
                    let edgeSpace = max(0, (geometry.size.width - transportWidth) / 2)
                    let diameter = min(56, max(30, edgeSpace - 16))
                    let inset = max(diameter / 2 + 8, min(geometry.size.width * 0.18, edgeSpace / 2))
                    PlayerSeekFeedback(seconds: seekFeedback, pulse: seekFeedbackPulse, diameter: diameter)
                        .position(x: seekFeedback < 0 ? inset : geometry.size.width - inset,
                                  y: geometry.size.height * 0.46)
                        .id(seekFeedback < 0)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                // TV output already displays its own connection status in
                // MediaVideoView; avoid stacking this player-level message on it.
                if playback.state == .loading && playback.tvName == nil && !playback.externalDisplayConnected {
                    ProgressView(L10n.tr("Yayın hazırlanıyor"))
                        .padding(16).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        .allowsHitTesting(false)
                }
                if let gestureAdjustment {
                    gestureAdjustmentHUD(gestureAdjustment, value: gestureAdjustmentValue)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .transition(.opacity)
                        .zIndex(4)
                        .allowsHitTesting(false)
                }
                if showingEdgeGestureIntro {
                    EdgeGestureIntro { showingEdgeGestureIntro = false; edgeGestureIntroShown = true }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.62))
                        .zIndex(5)
                }
                VStack(spacing: 0) {
                    header(isLandscape: geometry.size.width > geometry.size.height)
                    Spacer(minLength: 0)
                    if controlsVisible && !controlsLocked {
                        VStack(spacing: 8) {
                            if fullscreen {
                                PlaybackTimelineView(playback: playback) { isScrubbing = $0; revealControls() }
                                    .id(model.selectedMediaChannel?.id)
                            }
                            modeActions(compact: !fullscreen || geometry.size.width > geometry.size.height,
                                        vertical: geometry.size.height > geometry.size.width)
                        }
                        .padding(.horizontal, fullscreen ? 20 : 8).padding(.bottom, 8)
                    }
                }
                .padding(.top, fullscreen ? max(8, screenInsets.top) : 4)
                .padding(.bottom, fullscreen ? screenInsets.bottom : 0)
                .padding(.leading, fullscreen ? screenInsets.leading : 0)
                .padding(.trailing, fullscreen ? screenInsets.trailing : 0)
                .zIndex(1)
            }
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .sheet(isPresented: $showingChannels) { PlaybackQueueSheet(model: model) }
        .sheet(isPresented: $showingMediaChoices) { PlayerMediaChoicesView(playback: playback) }
        .onAppear {
            updateAwakeLease(); scheduleHide()
            if !edgeGestureIntroShown { showingEdgeGestureIntro = true }
        }
        .onDisappear {
            hideTask?.cancel(); clearSeekFeedback(); optionsTask?.cancel(); adjustmentHideTask?.cancel()
            MediaScreenAwake.release(awakeLease)
        }
        .onChange(of: fullscreen) { _, _ in showingOptions = false; clearSeekFeedback(); updateAwakeLease(); revealControls() }
        .onChange(of: playback.isPlaying) { _, _ in revealControls() }
        .onChange(of: controlsLocked) { _, _ in clearSeekFeedback(); revealControls() }
        .onChange(of: showingChannels) { _, _ in revealControls() }
        .onChange(of: showingMediaChoices) { _, _ in revealControls() }
        .onChange(of: showingOptions) { _, showing in
            revealControls()
            optionsTask?.cancel()
            if showing {
                optionsTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard !UIAccessibility.isVoiceOverRunning else { return }
                    showingOptions = false
                }
            }
        }
        .onChange(of: model.selectedMediaChannel?.id) { _, _ in
            showingOptions = false; showingMediaChoices = false; clearSeekFeedback(); revealControls()
        }
    }
    private func header(isLandscape: Bool) -> some View {
        HStack(spacing: 4) {
            if fullscreen && controlsVisible && !controlsLocked {
                VStack(alignment: .leading, spacing: 3) {
                    if largeControls {
                        Text(L10n.tr("Büyük kontroller")).font(.caption).foregroundStyle(MirrorStyle.accent)
                    }
                    Text(model.mediaTitle ?? BrandIdentity.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else { Spacer(minLength: 0) }
            if controlsLocked {
                iconButton("lock.open.fill", label: "Kilidi aç", id: "unlock-player-controls") { controlsLocked = false }
            } else if controlsVisible {
                if playback.hasMediaChoices {
                    iconButton("captions.bubble", label: "Ses ve altyazı", id: "player-media-options") { showingMediaChoices = true }
                }
                if fullscreen {
                    TVConnectionButton(model: model, compact: true)
                    iconButton("ellipsis", label: "Video seçenekleri", id: "player-options") { showingOptions.toggle() }
                        .popover(isPresented: $showingOptions, arrowEdge: .top) {
                        playerOptions(isLandscape: isLandscape).presentationCompactAdaptation(.popover)
                        }
                } else if playback.tvDevice == nil && !playback.externalDisplayConnected && !playback.externalPlaybackActive {
                    iconButton("arrow.up.left.and.arrow.down.right", label: "Tam ekran", id: "player-fullscreen") {
                        largeControls = false; displayMode = .normal; changeFullscreen(true)
                    }
                }
            }
        }.padding(.horizontal, fullscreen ? 16 : 4)
    }
    private func playerOptions(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            optionButton("Picture in Picture", icon: "pip.enter") { playback.startPictureInPicture() }
                .disabled(!playback.canStartPictureInPicture)
            if fullscreen && isLandscape {
                ForEach(PlayerVideoDisplayMode.allCases) { mode in
                    optionButton(mode.title, icon: mode.icon, selected: displayMode == mode) {
                        displayMode = mode
                    }
                }
            }
            optionButton("Kontrolleri kilitle", icon: "lock.fill") { controlsLocked = true }
            optionButton("Durdur", icon: "stop.fill", destructive: true) { model.stopPlayback() }
        }.padding(8).frame(minWidth: 240)
            .accessibilityElement(children: .contain).accessibilityIdentifier("player-options-popover")
    }
    private func optionButton(_ label: String, icon: String, destructive: Bool = false, selected: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            showingOptions = false
            action()
            revealControls()
        } label: {
            Label(L10n.tr(label), systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12).contentShape(Rectangle())
                .foregroundStyle(destructive ? .red : .white)
                .overlay(alignment: .trailing) {
                    if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(MirrorStyle.accent) }
                }
        }.buttonStyle(.plain)
    }
    private var transportControls: some View {
        HStack(spacing: fullscreen ? 28 : 20) {
            if playback.canSeek && (!fullscreen || !largeControls) {
                iconButton("gobackward.10", label: "10 saniye geri", id: "skip-backward") { skip(-10) }
            } else if model.playbackQueue.count > 1 {
                iconButton("backward.end.fill", label: "Önceki", id: "previous-channel") { model.switchChannel(-1) }
                    .disabled(model.adjacentChannel(-1) == nil)
            }
            Button { playback.togglePlayPause(); revealControls() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: fullscreen ? (largeControls ? 34 : 26) : 24, weight: .semibold))
                    .frame(width: fullscreen ? (largeControls ? 80 : 60) : 52,
                           height: fullscreen ? (largeControls ? 80 : 60) : 52)
                    .background(.black.opacity(0.25), in: Circle()).foregroundStyle(.white)
                    .overlay { Circle().strokeBorder(.white.opacity(0.18)) }
            }.accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
                .accessibilityIdentifier("player-play-pause")
            if playback.canSeek && (!fullscreen || !largeControls) {
                iconButton("goforward.10", label: "10 saniye ileri", id: "skip-forward") { skip(10) }
            } else if model.playbackQueue.count > 1 {
                iconButton("forward.end.fill", label: "Sonraki", id: "next-channel") { model.switchChannel(1) }
                    .disabled(model.adjacentChannel(1) == nil)
            }
        }
    }
    private func modeActions(compact: Bool, vertical: Bool) -> some View {
        HStack(spacing: vertical ? 5 : 8) {
            modeButton("Büyük kontroller", icon: "hand.tap", id: "player-large-controls", compact: compact,
                       vertical: vertical, selected: fullscreen && largeControls) {
                if !fullscreen { displayMode = .normal }
                largeControls = true; changeFullscreen(true); revealControls()
            }
            if fullscreen {
                modeButton("Tam ekran", icon: !largeControls ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           id: "player-fullscreen", compact: true, vertical: vertical, selected: !largeControls) {
                    if !largeControls { changeFullscreen(false) }
                    else { largeControls = false; changeFullscreen(true) }
                    revealControls()
                }
            } else {
                modeButton("Picture in Picture", icon: "pip.enter", id: "player-pip", compact: compact, vertical: vertical, selected: false) {
                    playback.startPictureInPicture(); revealControls()
                }.disabled(!playback.canStartPictureInPicture)
            }
            modeButton("Oynatma listesi", icon: "list.bullet", id: "player-channel-picker", compact: compact, vertical: vertical, selected: false) {
                showingChannels = true
            }.disabled(model.playbackQueue.isEmpty)
        }
    }
    private func modeButton(_ label: String, icon: String, id: String, compact: Bool, vertical: Bool = false, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: vertical ? 5 : 8) {
                Image(systemName: icon).font(.system(size: vertical ? 16 : 17, weight: .semibold))
                if !compact { Text(L10n.tr(label)).font(.system(size: vertical ? 11 : 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.78) }
            }.frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, vertical ? 3 : 8)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }.accessibilityLabel(L10n.tr(label)).accessibilityIdentifier(id)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func iconButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); revealControls() } label: {
            Image(systemName: icon).font(.system(size: fullscreen && largeControls ? 23 : 20, weight: .semibold))
                .frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
        }.accessibilityLabel(L10n.tr(label)).accessibilityIdentifier(id)
    }
    private func skip(_ seconds: Int) {
        guard playback.canSeek, !controlsLocked else { return }
        playback.seek(to: playback.currentTime + Double(seconds))
        feedbackTask?.cancel()
        withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.16)) { seekFeedback = seconds }
        seekFeedbackPulse += 1
        feedbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            withAnimation(.easeOut(duration: 0.18)) { seekFeedback = nil }
        }
        revealControls()
    }
    private func adjustBrightness(_ delta: CGFloat) {
        let value = min(1, max(0, UIScreen.main.brightness + delta))
        UIScreen.main.brightness = value
        showGestureAdjustment(.brightness, value: value)
    }
    private func handlePinch(_ scale: CGFloat) {
        guard !controlsLocked, !showingOptions, !showingEdgeGestureIntro else { return }
        if scale > 1.12 { displayMode = .fillScreen }
        else if scale < 0.88 { displayMode = .normal }
        revealControls()
    }
    private func showGestureAdjustment(_ adjustment: PlayerGestureAdjustment, value: CGFloat) {
        gestureAdjustment = adjustment
        gestureAdjustmentValue = min(1, max(0, value))
        adjustmentHideTask?.cancel()
        adjustmentHideTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { gestureAdjustment = nil }
        }
    }
    private func gestureAdjustmentHUD(_ adjustment: PlayerGestureAdjustment, value: CGFloat) -> some View {
        HStack(spacing: 14) {
            Image(systemName: adjustment.icon).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(adjustment.title).font(.caption.weight(.semibold))
                    Spacer(minLength: 12)
                    Text("\(Int((value * 100).rounded()))%").font(.caption.monospacedDigit())
                }
                ProgressView(value: value).tint(.white)
            }.frame(width: 156)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)) }
        .foregroundStyle(.white)
    }
    private func clearSeekFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        seekFeedback = nil
    }
    private func toggleControls() {
        guard !controlsLocked else { return }
        controlsVisible.toggle(); scheduleHide()
    }
    private func revealControls() { controlsVisible = true; scheduleHide() }
    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, playback.isPlaying, !controlsLocked, !showingChannels, !showingMediaChoices, !showingOptions, !isScrubbing,
              !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !UIAccessibility.isVoiceOverRunning else { return }
            controlsVisible = false
        }
    }
    private func updateAwakeLease() {
        if fullscreen && awakeLease == nil { awakeLease = MediaScreenAwake.acquire() }
        else if !fullscreen { MediaScreenAwake.release(awakeLease); awakeLease = nil }
    }
}

private struct PlayerMediaChoicesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var playback: PlaybackController
    var body: some View {
        NavigationStack {
            List {
                if playback.audioTracks.count > 1 {
                    Section(L10n.tr("Ses dili")) {
                        ForEach(playback.audioTracks) { track in
                            choice(track.title, selected: track.isSelected, id: "audio-track-\(track.id)") {
                                playback.selectAudioTrack(track.id)
                            }
                        }
                    }
                }
                if !playback.subtitleTracks.isEmpty {
                    Section(L10n.tr("Altyazı")) {
                        if playback.canDisableSubtitles {
                            choice(L10n.tr("Kapalı"), selected: !playback.subtitleTracks.contains(where: \.isSelected), id: "subtitles-off") {
                                playback.selectSubtitleTrack(nil)
                            }
                        }
                        ForEach(playback.subtitleTracks) { track in
                            choice(track.title, selected: track.isSelected, id: "subtitle-track-\(track.id)") {
                                playback.selectSubtitleTrack(track.id)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .navigationTitle(L10n.tr("Ses ve altyazı")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Kapat"), systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("close-media-options")
                }
            }
        }
        .tint(MirrorStyle.accent).preferredColorScheme(.dark)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 8)
                Image(systemName: "checkmark").foregroundStyle(MirrorStyle.accent).opacity(selected ? 1 : 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.listRowBackground(MirrorStyle.surface).accessibilityIdentifier(id)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A brief direction cue in the free space beside the transport controls.
private struct EdgeGestureIntro: View {
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: proxy.size.height < 360 ? 10 : 16) {
                    Image(systemName: "hand.draw.fill").font(.system(size: 28)).foregroundStyle(MirrorStyle.accent)
                    Text(L10n.tr("Yatay tam ekran hareketleri"))
                        .font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        introLine("Sağ kenardan yukarı/aşağı: ses", icon: "speaker.wave.2.fill")
                        introLine("Sol kenardan yukarı/aşağı: parlaklık", icon: "sun.max.fill")
                        introLine("Sıkıştırıp yakınlaştır: ekranı doldur", icon: "arrow.up.left.and.arrow.down.right")
                        introLine("Sıkıştırıp uzaklaştır: normal görünüme dön", icon: "arrow.down.right.and.arrow.up.left")
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    Button(L10n.tr("Tamam"), action: dismiss)
                        .buttonStyle(MirivoButtonStyle(prominent: true))
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
                .frame(maxWidth: 390)
                .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(MirrorStyle.hairline) }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: min(440, proxy.size.height))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("player-edge-gesture-intro")
        }
    }

    private func introLine(_ key: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).padding(.top, 2)
            Text(L10n.tr(key)).fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

private struct PlayerSeekFeedback: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationTrigger = 0
    let seconds: Int
    let pulse: Int
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: seconds < 0 ? "backward.fill" : "forward.fill")
                .font(.system(size: diameter * 0.23, weight: .semibold))
                .foregroundStyle(MirrorStyle.accent)
            Text(seconds < 0 ? "−\(abs(seconds))" : "+\(seconds)")
                .font(.system(size: diameter * 0.34, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .background(.black.opacity(0.22), in: Circle())
        .overlay {
            if !reduceMotion {
                PhaseAnimator([0, 1, 2], trigger: animationTrigger) { phase in
                    Circle().strokeBorder(MirrorStyle.accent.opacity(phase == 1 ? 0.28 : 0), lineWidth: 1)
                        .scaleEffect(phase == 0 ? 0.82 : phase == 1 ? 1 : 1.18)
                } animation: { phase in
                    .easeOut(duration: phase == 1 ? 0.12 : 0.26)
                }
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: pulse, initial: true) { _, value in animationTrigger = value }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr(seconds < 0 ? "10 saniye geri" : "10 saniye ileri"))
        .accessibilityIdentifier("player-seek-feedback")
    }
}

/// Recognizers share one clear surface, so single taps wait for double taps and
/// pan/pinch never compete with the timeline or SwiftUI buttons above it.
private struct PlayerGestureSurface: UIViewRepresentable {
    var locked: Bool
    var fullscreen: Bool
    var singleTap: () -> Void
    var doubleTap: (Int) -> Void
    var swipeDown: () -> Void
    var adjustBrightness: (CGFloat) -> Void
    var adjustVolume: (CGFloat) -> Void
    var pinchEnded: (CGFloat) -> Void
    var safeAreaChanged: (EdgeInsets) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.insetsChanged = safeAreaChanged
        view.installVolumeView()
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        view.addGestureRecognizer(single); view.addGestureRecognizer(double)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.require(toFail: double)
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false
        pinch.require(toFail: double)
        view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ view: GestureView, context: Context) {
        context.coordinator.parent = self
        view.insetsChanged = safeAreaChanged
        view.gestureRecognizers?.forEach { recognizer in
                    let fullscreenOnly = recognizer is UIPanGestureRecognizer || recognizer is UIPinchGestureRecognizer
            recognizer.isEnabled = !locked && (!fullscreenOnly || fullscreen)
        }
    }
    @MainActor final class GestureView: UIView {
        var insetsChanged: ((EdgeInsets) -> Void)?
        private var reportedInsets: EdgeInsets?
        private let volumeView = MPVolumeView(frame: CGRect(x: -220, y: 0, width: 200, height: 40))
        func installVolumeView() {
            volumeView.showsRouteButton = false
            volumeView.alpha = 0.001
            addSubview(volumeView)
        }
        func adjustVolume(by delta: CGFloat) -> CGFloat? {
            volumeView.layoutIfNeeded()
            guard let slider = volumeSlider(in: volumeView) else { return nil }
            slider.value = min(1, max(0, slider.value + Float(delta)))
            slider.sendActions(for: .valueChanged)
            return CGFloat(slider.value)
        }
        private func volumeSlider(in view: UIView) -> UISlider? {
            if let slider = view as? UISlider { return slider }
            for child in view.subviews {
                if let slider = volumeSlider(in: child) { return slider }
            }
            return nil
        }
        override func didMoveToWindow() { super.didMoveToWindow(); publishInsets() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); publishInsets() }
        override func layoutSubviews() { super.layoutSubviews(); publishInsets() }
        private func publishInsets() {
            guard let insets = window?.safeAreaInsets else { return }
            let value = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
            guard reportedInsets != value else { return }
            reportedInsets = value
            Task { @MainActor [weak self] in self?.insetsChanged?(value) }
        }
    }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerGestureSurface
        private var panMode: PanMode = .none
        private var lastPanY: CGFloat = 0
        private enum PanMode: Equatable { case none, volume, brightness, exit }
        init(_ parent: PlayerGestureSurface) { self.parent = parent }
        @objc func tap() { parent.singleTap() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            parent.doubleTap(gesture.location(in: view).x < view.bounds.midX ? -10 : 10)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard parent.fullscreen else { return }
            if gesture.state == .ended { parent.pinchEnded(gesture.scale) }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer) &&
                (otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer)
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard parent.fullscreen, let view = gesture.view else { return }
            let point = gesture.location(in: view)
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                if view.bounds.width > view.bounds.height {
                    let edgeWidth = view.bounds.width * 0.18
                    if point.x >= view.bounds.maxX - edgeWidth { panMode = .volume }
                    else if point.x <= view.bounds.minX + edgeWidth { panMode = .brightness }
                    else { panMode = .exit }
                } else { panMode = .exit }
                lastPanY = translation.y
            case .changed:
                let delta = (lastPanY - translation.y) / max(view.bounds.height, 1)
                lastPanY = translation.y
                if delta != 0 {
                    switch panMode {
                    case .volume:
                        if let value = (view as? GestureView)?.adjustVolume(by: delta) { parent.adjustVolume(value) }
                    case .brightness: parent.adjustBrightness(delta)
                    case .none, .exit: break
                    }
                }
            case .ended:
                if panMode == .exit && translation.y > 80 && translation.y > abs(translation.x) * 1.3 {
                    parent.swipeDown()
                }
                panMode = .none
            case .cancelled, .failed:
                panMode = .none
            default: break
            }
        }
    }
}

private struct PlaybackQueueSheet: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ChannelBrowserView(channels: model.playbackQueue,
                               title: model.playbackSource?.name ?? L10n.tr("Oynatma listesi"),
                               sourceID: model.playbackSourceID,
                               playlistChannels: model.playbackQueue,
                               onSelectChannel: { channel in
                                   if model.playMedia(channel, queue: model.playbackQueue,
                                                      sourceID: model.playbackSourceID) {
                                       dismiss()
                                   } else if let error = model.errorMessage {
                                       message = error
                                       model.errorMessage = nil
                                   }
                               })
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .task { await model.restorePlaybackQueueFromSource() }
            .alert(BrandIdentity.name, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(L10n.tr("Tamam")) { message = nil }
            } message: { Text(message ?? "") }
    }
}
