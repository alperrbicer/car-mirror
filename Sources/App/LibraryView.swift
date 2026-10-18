import SwiftUI
import AVKit
import MediaPlayer
import UniformTypeIdentifiers

enum PlayerVideoDisplayMode: String, CaseIterable, Identifiable {
    case normal
    case fitScreen
    case fillScreen

    var id: String { rawValue }
    func effective(fullscreen: Bool, landscape: Bool) -> Self {
        fullscreen && landscape ? self : .normal
    }
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

    static func landscapeEdge(at x: CGFloat, width: CGFloat) -> Self? {
        guard width > 0 else { return nil }
        let edgeWidth = width * 0.18
        if x >= width - edgeWidth { return .volume }
        if x <= edgeWidth { return .brightness }
        return nil
    }
}

enum PlayerFullscreenExitGesture {
    static func shouldExit(translation: CGSize, velocity: CGSize) -> Bool {
        guard translation.height > abs(translation.width) * 1.3 else { return false }
        let draggedDown = translation.height >= 64
        let flickedDown = translation.height >= 24 && velocity.height >= 550 &&
            velocity.height > abs(velocity.width) * 1.3
        return draggedDown || flickedDown
    }
}

enum PlayerFullscreenRotationPolicy {
    static func suppressAutomaticLandscape(fullscreen: Bool, landscape: Bool) -> Bool {
        fullscreen && landscape
    }
}

struct LibraryView: View {
    let openPlayer: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var model = MirrorModel.shared
    @State private var sourceEditorRoute: SourceEditorRoute?
    @State private var refreshingSources: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            libraryHeader
            NavigationLink { FavoritesBrowser(model: model) } label: {
                Label(L10n.tr("Favoriler"), systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 18).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("open-favorites")
            ContinueWatchingSection(openPlayer: openPlayer)
            OfflineDownloadsSection()
            if library.sources.isEmpty {
                emptyLibrary
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(L10n.tr("Kayıtlı kaynaklar")).font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(library.sources.count, format: .number)
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(MirrorStyle.accent)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(MirrorStyle.accent.opacity(0.1), in: Capsule())
                    }.accessibilityElement(children: .combine)
                    ForEach(library.sources) { source in
                        HStack(spacing: 0) {
                            NavigationLink(value: source.id) {
                                HStack(spacing: 16) {
                                    if !dynamicTypeSize.isAccessibilitySize {
                                        Image(systemName: source.kind == .xtream ? "server.rack" : "play.rectangle")
                                            .font(.title3).foregroundStyle(MirrorStyle.accent)
                                            .frame(width: 48, height: 56)
                                            .background {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(LinearGradient(colors: [MirrorStyle.accent.opacity(0.18), MirrorStyle.accent.opacity(0.04)],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                            }
                                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MirrorStyle.accent.opacity(0.16)) }
                                            .accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(source.name).font(.headline).foregroundStyle(.white)
                                        Text(L10n.tr(source.kind == .xtream ? "IPTV sunucusu" : source.kind == .stream ? "Yayın bağlantısı" : "Oynatma listesi"))
                                            .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                        SourceExpiryView(source: source)
                                    }
                                    Spacer(minLength: 4)
                                    if !dynamicTypeSize.isAccessibilitySize {
                                        Image(systemName: "chevron.forward")
                                            .font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
                                            .accessibilityHidden(true)
                                    }
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
                                    sourceEditorRoute = .edit(SourceEditDraft(source: source))
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
                                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
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
            if library.sources.isEmpty { addSourceButton }

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
        .sheet(item: $sourceEditorRoute) { route in
            switch route {
            case .add(let kind): SourceEditorView(initialKind: kind)
            case .edit(let draft): SourceEditorView(source: draft.source)
            }
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button(L10n.tr("Tamam")) { library.message = nil }
        } message: { Text(library.message ?? "") }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Text(L10n.tr(library.sources.isEmpty ? "Kaynakların burada" : "Kaynaklar"))
                    .font(.largeTitle.weight(.semibold))
                    .tracking(L10n.appLanguage.allowsLetterSpacing ? -1 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if !library.sources.isEmpty {
                    Button { add() } label: {
                        Label(L10n.tr("Ekle"), systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MirrorStyle.accent)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(MirrorStyle.accent.opacity(0.1), in: Capsule())
                            .overlay { Capsule().strokeBorder(MirrorStyle.accent.opacity(0.2)) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(MirivoPressButtonStyle())
                    .accessibilityLabel(L10n.tr("Kaynak ekle"))
                    .accessibilityIdentifier("add-source")
                }
            }
            Text(L10n.tr(library.sources.isEmpty
                         ? "Bir oynatma listesi, yayın bağlantısı veya IPTV sunucusu ekle."
                         : "Sevdiğin içerikler, tek yerde."))
                .font(.subheadline).foregroundStyle(MirrorStyle.secondary).lineSpacing(4)
        }.fixedSize(horizontal: false, vertical: true)
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
            }.frame(maxWidth: .infinity).frame(height: 140).accessibilityHidden(true)
            VStack(spacing: 0) {
                sourceType("Oynatma listesi", detail: "M3U", icon: "list.bullet.rectangle", kind: .playlist)
                Rectangle().fill(MirrorStyle.hairline).frame(height: 1)
                sourceType("Yayın bağlantısı", detail: "URL", icon: "link", kind: .stream)
                Rectangle().fill(MirrorStyle.hairline).frame(height: 1)
                sourceType("IPTV sunucusu", detail: "Xtream Codes", icon: "server.rack", kind: .xtream)
                Divider().overlay(MirrorStyle.hairline)
                sourceType("Dosyadan oynatma listesi", detail: "M3U / M3U8", icon: "doc", kind: .playlistFile)
            }.padding(.horizontal, 22).padding(.bottom, 8)
        }
        .background(MirrorStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.hairline) }
    }

    private func sourceType(_ title: String, detail: String, icon: String, kind: MediaSourceKind) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return Button { add(kind: kind) } label: {
            layout {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 18)).frame(width: 22)
                        .foregroundStyle(MirrorStyle.accent).accessibilityHidden(true)
                    Text(L10n.tr(title)).font(.subheadline).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                HStack(spacing: 8) {
                    Text(detail).font(.caption).foregroundStyle(MirrorStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "plus.circle").foregroundStyle(MirrorStyle.accent).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 4)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
        }.buttonStyle(.plain).accessibilityIdentifier("add-source-\(kind.rawValue)")
    }

    private var addSourceButton: some View {
        Button { add() } label: {
            Label(L10n.tr("Kaynak ekle"), systemImage: "plus")
        }.buttonStyle(MirivoButtonStyle(prominent: true)).accessibilityIdentifier("add-source")
    }

    private func add(kind: MediaSourceKind = .playlist) {
        sourceEditorRoute = .add(kind)
    }
}

private enum SourceEditorRoute: Identifiable {
    case add(MediaSourceKind)
    case edit(SourceEditDraft)

    var id: String {
        switch self {
        case .add(let kind): "add-\(kind.rawValue)"
        case .edit(let draft): "edit-\(draft.id.uuidString)"
        }
    }
}

private struct ContinueWatchingSection: View {
    let openPlayer: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var history = LastPlaybackStore.shared
    @ObservedObject private var library = SourceLibrary.shared
    @ObservedObject private var model = MirrorModel.shared
    @ObservedObject private var playback = MirrorModel.shared.playback
    @State private var showingAll = false
    @State private var pendingResume: LastPlaybackRecord?
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
                    }.scrollIndicators(.hidden).accessibilityIdentifier("continue-watching-carousel")
                }.accessibilityElement(children: .contain).accessibilityIdentifier("continue-watching-section")
            }
        }
        .sheet(isPresented: $showingAll, onDismiss: {
            guard let entry = pendingResume else { return }
            pendingResume = nil
            resume(entry)
        }) {
            NavigationStack {
                List {
                    ForEach(filtered) { entry in
                        Button { resume(entry) } label: {
                            let layout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                : AnyLayout(HStackLayout(spacing: 14))
                            layout {
                                ContinueWatchingArtwork(entry: entry).frame(width: 58, height: 87)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.seriesTitle ?? entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    if let episode = entry.episode {
                                        Text(SeriesText.episode(episode)).font(.caption).foregroundStyle(MirrorStyle.secondary)
                                    }
                                    ContinueWatchingProgress(entry: entry)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 96)
                                .padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("continue-list-open-\(entry.id)")
                            .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .topTrailing : .trailing) {
                                HStack(spacing: 0) {
                                    MediaFavoriteButton(channel: entry.channel, sourceID: entry.sourceID, compact: true,
                                                        identifier: "continue-list-favorite-" + entry.id)
                                    ContinueWatchingRemoveMenu(entry: entry, identifierPrefix: "continue-list", remove: { remove(entry) })
                                }.padding(.top, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                            }
                            .listRowBackground(MirrorStyle.surface)
                            .swipeActions {
                                Button(role: .destructive) { remove(entry) } label: {
                                    Label(L10n.tr("Listeden kaldır"), systemImage: "trash")
                                }
                                .tint(.red)
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
        if showingAll {
            pendingResume = entry
            showingAll = false
            return
        }
        if model.resumePlayback(entry) { openPlayer() }
        else {
            guard !model.requiresMembership else { return }
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
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L10n.tr("İndirilenler")).font(.headline).foregroundStyle(.white)
                            if !downloads.items.isEmpty {
                                Text(downloads.items.count.formatted()).font(.caption.monospacedDigit())
                                    .foregroundStyle(MirrorStyle.accent)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(MirrorStyle.accent.opacity(0.1), in: Capsule())
                            }
                        }
                        Text(L10n.tr("Uygun film ve bölümleri indir, internet olmadan izle."))
                            .font(.caption).foregroundStyle(MirrorStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
                        .accessibilityHidden(true)
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
    @ObservedObject private var library = SourceLibrary.shared
    @State private var showingPlayer = false
    @State private var favoriteChannels: [UUID: MediaChannel] = [:]
    var body: some View {
        List {
            if downloads.items.isEmpty {
                ContentUnavailableView(L10n.tr("Henüz indirilen içerik yok"), systemImage: "arrow.down.circle",
                                       description: Text(L10n.tr("Film veya bölüm listesindeki indirme düğmesine dokun. İndirdiklerin burada görünür.")))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
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
                            .accessibilityIdentifier("offline-item-\(item.id)")
                    } else {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.title).font(.headline)
                            if item.state == .failed {
                                Text(item.failureMessage ?? L10n.tr("İndirme başarısız"))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            else { progressLabel(item) }
                        }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }
                    if let original = favoriteChannels[item.id] {
                        MediaFavoriteButton(channel: original, sourceID: item.sourceID, compact: true,
                                            identifier: "offline-favorite-" + item.id.uuidString)
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
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(L10n.tr("İndirilenler")).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        .safeAreaInset(edge: .bottom) { NowPlayingBar { showingPlayer = true } }
        .task(id: downloads.items.map(\.id) + library.sources.map(\.id)) {
            favoriteChannels = [:]
            let sourceIDs = Set(downloads.items.compactMap(\.sourceID))
            for source in library.sources where sourceIDs.contains(source.id) {
                if let cached = library.cachedChannels(for: source) {
                    resolveFavorites(in: cached, sourceID: source.id)
                } else {
                    // The encrypted source cache can resolve old downloads offline,
                    // without copying provider URLs into the download manifest.
                    let channels = try? await library.channels(for: source, onCached: { channels in
                        guard !Task.isCancelled else { return }
                        resolveFavorites(in: channels, sourceID: source.id)
                    })
                    guard !Task.isCancelled else { return }
                    if let channels { resolveFavorites(in: channels, sourceID: source.id) }
                }
            }
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { downloads.message != nil }, set: { if !$0 { downloads.clearMessage() } })) {
            Button(L10n.tr("Tamam")) { downloads.clearMessage() }
        } message: { Text(downloads.message ?? "") }
    }
    private func resolveFavorites(in channels: [MediaChannel], sourceID: UUID) {
        let resolved = OfflineDownload.originalChannels(for: downloads.items, in: channels, sourceID: sourceID)
        for item in downloads.items where item.sourceID == sourceID {
            favoriteChannels[item.id] = resolved[item.id]
        }
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

/// Present above the entire card so its sibling favorite control cannot bleed through.
private struct ContinueWatchingRemoveMenu: View {
    let entry: LastPlaybackRecord
    let identifierPrefix: String
    let remove: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MirrorStyle.secondary)
                .frame(width: 32, height: 32)
                .background(MirrorStyle.raised, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(MirivoPressButtonStyle())
        .accessibilityLabel(entry.title)
        .accessibilityIdentifier("\(identifierPrefix)-menu-\(entry.id)")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Button(role: .destructive) {
                isPresented = false
                remove()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "trash")
                        .foregroundStyle(MirrorStyle.accent)
                    Text(L10n.tr("Listeden kaldır"))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(minHeight: MirrorStyle.controlHeight, alignment: .leading)
                .contentShape(Capsule())
            }
            .buttonStyle(MirivoPressButtonStyle())
            .accessibilityIdentifier("\(identifierPrefix)-remove-\(entry.id)")
            .background(MirrorStyle.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(MirrorStyle.hairline) }
            .padding(6)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(MirrorStyle.raised)
            .presentationCornerRadius(36)
            .preferredColorScheme(.dark)
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
            VStack(alignment: .leading, spacing: 16) {
                artworkLayout {
                    ContinueWatchingArtwork(entry: entry)
                        .frame(width: 76, height: 114)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MirrorStyle.background).frame(width: 30, height: 30)
                                .background(MirrorStyle.accent, in: Circle()).padding(6)
                        }.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.seriesTitle ?? entry.title).font(.headline).foregroundStyle(.white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        if let episode = entry.episode {
                            Text(SeriesText.episode(episode)).font(.caption).foregroundStyle(MirrorStyle.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !entry.group.isEmpty {
                            Text(entry.group).font(.caption).foregroundStyle(MirrorStyle.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : 30)
                }
                ContinueWatchingProgress(entry: entry)
            }.padding(16).frame(width: 300)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("continue-watching-open-\(entry.id)")
            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    MediaFavoriteButton(channel: entry.channel, sourceID: entry.sourceID,
                                        compact: true, identifier: "continue-watching-favorite-" + entry.id)
                    ContinueWatchingRemoveMenu(entry: entry, identifierPrefix: "continue-watching", remove: remove)
                }.padding(6)
            }
    }
    private var artworkLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
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
    var id: UUID { source.id }
}

private struct SourceEditorView: View {
    private let source: MediaSource?
    @State private var originalSecret: SourceSecret?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var kind: MediaSourceKind = .playlist
    @State private var message: String?
    @State private var selectingFile = false
    @State private var selectedFile: URL?
    @State private var isLoadingSource: Bool
    init(source: MediaSource? = nil, secret: SourceSecret? = nil, initialKind: MediaSourceKind = .playlist) {
        self.source = source
        _originalSecret = State(initialValue: secret)
        _name = State(initialValue: source?.name ?? "")
        _kind = State(initialValue: source?.kind ?? initialKind)
        _address = State(initialValue: secret?.url.absoluteString ?? "")
        _username = State(initialValue: secret?.username ?? "")
        _password = State(initialValue: secret?.password ?? "")
        _isLoadingSource = State(initialValue: source != nil && secret == nil)
    }
    private var canSave: Bool {
        guard !isLoadingSource else { return false }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind == .playlistFile { return selectedFile != nil || (source?.kind == .playlistFile && originalSecret != nil) }
        guard let url = try? MediaURL.validate(address) else { return false }
        return kind != .xtream || (try? XtreamEndpoint.playlist(secret: SourceSecret(url: url, username: username, password: password))) != nil
    }
    private var addressPlaceholder: String {
        switch kind {
        case .xtream: "https://server.example"
        case .stream: "https://example.com/video.mp4"
        default: "https://example.com/playlist.m3u"
        }
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
                        TextField(L10n.tr("Kaynak adresi"), text: $address, prompt: Text(verbatim: addressPlaceholder))
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
                } header: {
                    Text(L10n.tr(kind == .xtream ? "IPTV sunucusu" : kind == .stream ? "Yayın bağlantısı" : "Oynatma listesi"))
                } footer: { Text(L10n.tr("Mirivo içerik sağlamaz. Erişim hakkına sahip olduğun kaynakları ekleyebilirsin. Adres ve giriş bilgileri cihazındaki Keychain’de saklanır.")) }
                    .listRowBackground(MirrorStyle.surface)
                if let message { Section { Text(message).foregroundStyle(.red) }.listRowBackground(MirrorStyle.surface) }
                if isLoadingSource {
                    Section { ProgressView().frame(maxWidth: .infinity, alignment: .center) }
                        .listRowBackground(MirrorStyle.surface)
                }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Text(L10n.tr(source == nil ? "Ekle" : "Kaydet"))
                            .frame(minWidth: 44, minHeight: 44)
                    }.disabled(!canSave)
                }
            }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
            .task(id: source?.id) {
                guard let source, originalSecret == nil else { return }
                let sourceID = source.id
                do {
                    let secret = try await Task.detached(priority: .userInitiated) {
                        try SourceKeychain.read(sourceID)
                    }.value
                    guard !Task.isCancelled else { return }
                    originalSecret = secret
                    address = secret.url.absoluteString
                    username = secret.username ?? ""
                    password = secret.password ?? ""
                    isLoadingSource = false
                } catch {
                    guard !Task.isCancelled else { return }
                    isLoadingSource = false
                    message = L10n.tr("Kaynaklar açılamadı. Lütfen yeniden dene.")
                }
            }
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
        var outcome = MeasurementEvent.Outcome.failure
        defer {
            AppMeasurement.shared.record(MeasurementEvent(name: .sourceSave, outcome: outcome,
                sourceKind: kind, operation: source == nil ? .add : .update))
        }
        do {
            if kind == .playlistFile {
                if let selectedFile {
                    try SourceLibrary.shared.importPlaylist(selectedFile, name: name, replacing: source, access: PurchaseStore.shared.access)
                } else if let source, let originalSecret, source.kind == .playlistFile {
                    try SourceLibrary.shared.update(source, name: name, kind: kind, secret: originalSecret)
                } else { throw LibraryError.invalidURL }
                outcome = .success
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
            outcome = .success
            dismiss()
        } catch {
            AppMeasurement.shared.failure(.sourceSave, error: error)
            message = kind == .playlistFile ? L10n.tr("Oynatma listesi dosyası açılamadı. M3U veya M3U8 dosyası seç.") : L10n.tr(source == nil ? "Kaynak eklenemedi. Adresi ve giriş bilgilerini kontrol et." : "Kaynak güncellenemedi. Adresi ve giriş bilgilerini kontrol et.")
        }
    }
}

struct ChannelListView: View {
    let source: MediaSource
    let onInitialContentReady: (() -> Void)?
    let onOpenSettings: () -> Void
    let onSelectSource: (UUID) -> Void
    @ObservedObject private var library = SourceLibrary.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var channels: [MediaChannel] = []
    @State private var loading = true
    @State private var message: String?
    @State private var refreshID = UUID()
    init(source: MediaSource, onInitialContentReady: (() -> Void)? = nil,
         onOpenSettings: @escaping () -> Void, onSelectSource: @escaping (UUID) -> Void) {
        self.source = source
        self.onInitialContentReady = onInitialContentReady
        self.onOpenSettings = onOpenSettings
        self.onSelectSource = onSelectSource
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
                                   playlistChannels: channels, onOpenSettings: onOpenSettings)
            }
        }
        .background(MirrorStyle.background)
        .navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        .task(id: loading || onInitialContentReady == nil) {
            guard !loading, let onInitialContentReady else { return }
            await MediaArtworkStore.shared.prepareInitialArtwork(for: channels)
            guard !Task.isCancelled else { return }
            onInitialContentReady()
        }
        .task(id: source) { await SourceLibrary.shared.accounts.refresh(for: source) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SourceLibrary.shared.accounts.refresh(for: source) } }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if library.sources.count > 1 {
                ToolbarTitleMenu {
                    Picker(L10n.tr("Kaynaklar"), selection: Binding(get: { source.id }, set: onSelectSource)) {
                        ForEach(library.sources) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("source-switcher")
                }
            }
        }
        .refreshable {
            async let accountRefresh: () = SourceLibrary.shared.accounts.refresh(for: source, force: true)
            do { channels = try await SourceLibrary.shared.channels(for: source, reload: true) }
            catch is CancellationError { }
            catch { SourceLibrary.shared.message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
            await accountRefresh
        }
        .task(id: refreshID) {
            // Keep the browser visible while an expired snapshot refreshes.
            loading = channels.isEmpty && SourceLibrary.shared.cachedChannels(for: source) == nil
            message = nil
            defer { loading = false }
            do {
                channels = try await SourceLibrary.shared.channels(for: source, onCached: { saved in
                    channels = saved
                    loading = false
                })
            }
            catch is CancellationError { }
            catch { message = L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.") }
        }
    }
}

private struct ChannelSearchBar: View {
    @Binding var text: String
    let prompt: String
    var onEditingChanged: ((Bool) -> Void)?
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 12) {
            ChannelSearchTextField(text: $text, isEditing: $isEditing, prompt: prompt)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .modifier(SearchControlSurface())
            if isEditing {
                Button { isEditing = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 21, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .modifier(SearchControlSurface())
                        .contentShape(Capsule())
                }
                .buttonStyle(MirivoPressButtonStyle())
                .accessibilityLabel(L10n.tr("Klavyeyi kapat"))
                .accessibilityIdentifier("dismiss-channel-search-keyboard")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .onChange(of: isEditing) { _, editing in onEditingChanged?(editing) }
        .onDisappear { isEditing = false }
    }
}

private struct SearchControlSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(MirrorStyle.raised, in: Capsule())
                .overlay { Capsule().strokeBorder(MirrorStyle.hairline) }
        }
    }
}

/// Keep the native search field and its clear-text control, while the adjacent
/// button only ends editing instead of cancelling and clearing the search.
private struct ChannelSearchTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UISearchTextField {
        let field = UISearchTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.tintColor = UIColor(MirrorStyle.accent)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityTraits.insert(.searchField)
        field.accessibilityIdentifier = "channel-search-field"
        return field
    }
    func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.placeholder = prompt
        field.accessibilityLabel = prompt
        field.semanticContentAttribute = context.environment.layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        if !isEditing { field.endEditing(true) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISearchTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(28, size.height))
    }
    static func dismantleUIView(_ field: UISearchTextField, coordinator: Coordinator) {
        field.delegate = nil
        field.resignFirstResponder()
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChannelSearchTextField
        init(parent: ChannelSearchTextField) { self.parent = parent }
        @objc func textChanged(_ field: UISearchTextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isEditing { parent.isEditing = true }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isEditing { parent.isEditing = false }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

struct ChannelBrowserView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var downloads = OfflineDownloadStore.shared
    let channels: [MediaChannel]
    let title: String
    var sourceID: UUID?
    var showsCategories = true
    var showsSearch = true
    var playlistChannels: [MediaChannel]?
    var onSelectChannel: ((MediaChannel) -> Void)?
    var onOpenSettings: (() -> Void)?
    @State private var query = ""
    @State private var selectedSeason: Int
    @State private var episodeMetadata: [String: MediaMetadata] = [:]
    @State private var playbackMessage: String?
    @State private var showingPlayer = false
    @AppStorage private var sortMode: MediaLibrarySort
    // nil means the initial recency lookup is still unresolved. Do not show
    // provider-ordered rows before the selected sort can be applied.
    @State private var addedDates: [String: Date]?
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [MediaChannel] {
        if searchTerm.isEmpty {
            if let series { return series.seasons.first(where: { $0.number == selectedSeason })?.channels ?? [] }
            return sortedChannels(channels)
        }
        let matches = channels.filter {
            $0.title.localizedStandardContains(searchTerm) || $0.group.localizedStandardContains(searchTerm)
        }
        return series == nil ? sortedChannels(matches) : matches
    }
    private let categories: [MediaChannelCategory]
    private let seriesCatalog: MediaSeriesCatalog
    private let series: MediaSeries?
    private var episodeMetadataRequestID: [String] {
        // Restoring a playback queue can add episodes to the same series.
        [sourceID?.uuidString ?? "", series?.id ?? ""] + (series?.channels.map(\.id) ?? [])
    }
    private let isMovieList: Bool
    private var filteredSeries: [MediaSeries] {
        let matches = searchTerm.isEmpty ? seriesCatalog.series : seriesCatalog.series.filter { item in
            item.title.localizedStandardContains(searchTerm) || item.group.localizedStandardContains(searchTerm) ||
                item.channels.contains { $0.title.localizedStandardContains(searchTerm) }
        }
        return matches
    }
    private var ungrouped: [MediaChannel] {
        let matches = searchTerm.isEmpty ? seriesCatalog.ungrouped : seriesCatalog.ungrouped.filter {
            $0.title.localizedStandardContains(searchTerm) || $0.group.localizedStandardContains(searchTerm)
        }
        return sortedChannels(matches)
    }
    private var canSort: Bool { isMovieList && showsChannelRows }
    private var loadingAddedDates: Bool { canSort && sortMode == .recentlyAdded && addedDates == nil }
    private var recencyUnavailable: Bool { addedDates != nil && channels.contains { addedDate($0) == nil } }
    private func addedDate(_ channel: MediaChannel) -> Date? { addedDates?[channel.id] ?? channel.metadata.addedAt }
    private func sortedChannels(_ channels: [MediaChannel]) -> [MediaChannel] {
        canSort && !loadingAddedDates ? sortMode.sorted(channels, title: { $0.title }, addedAt: addedDate) : channels
    }

    @ViewBuilder private var sortMenu: some View {
        if canSort {
            Menu {
                Picker(L10n.tr("Sırala"), selection: $sortMode) {
                    ForEach(MediaLibrarySort.allCases) { mode in
                        Text(L10n.tr(mode.title)).tag(mode)
                    }
                }
                if sortMode == .recentlyAdded && recencyUnavailable {
                    Text(L10n.tr("Ekleme tarihi paylaşılmayan içerikler kaynak sırasını korur."))
                }
            } label: {
                HStack(spacing: 5) {
                    if loadingAddedDates { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.up.arrow.down") }
                    Text(L10n.tr(sortMode == .provider ? "Sırala" : sortMode.title)).lineLimit(1)
                }
                .font(.caption.weight(.medium)).foregroundStyle(MirrorStyle.accent)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(MirrorStyle.accent.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
            }
            .textCase(nil).accessibilityLabel(L10n.tr("Sırala"))
            .accessibilityValue(L10n.tr(sortMode.title)).accessibilityIdentifier("library-sort")
        }
    }
    init(channels: [MediaChannel], title: String, sourceID: UUID? = nil, showsCategories: Bool = true,
         playlistChannels: [MediaChannel]? = nil, onSelectChannel: ((MediaChannel) -> Void)? = nil,
         series: MediaSeries? = nil, initialSeason: Int? = nil, showsSearch: Bool = true,
         sortScope: String = "all", onOpenSettings: (() -> Void)? = nil) {
        self.channels = channels; self.title = title; self.sourceID = sourceID
        self.showsCategories = showsCategories; self.playlistChannels = playlistChannels
        self.onSelectChannel = onSelectChannel
        self.onOpenSettings = onOpenSettings
        self.showsSearch = showsSearch
        let categories = showsCategories ? MediaChannelCategory.group(channels) : []
        self.categories = categories
        self.series = series
        isMovieList = series == nil && !channels.isEmpty && channels.allSatisfy(\.isMovie)
        // The source and list each own a preference. Ignore the old global
        // key so previous selections cannot override the movie-list default.
        let scope = [sourceID?.uuidString ?? "local", sortScope]
        let key = "library.movieSort." + scope.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
        _sortMode = AppStorage(wrappedValue: .recentlyAdded, key)
        _addedDates = State(initialValue: sourceID == nil || channels.allSatisfy { $0.metadata.addedAt != nil } ? [:] : nil)
        _selectedSeason = State(initialValue: initialSeason ?? series?.seasons.first?.number ?? 1)
        seriesCatalog = series == nil && (!showsCategories || !categories.contains(where: { !$0.name.isEmpty }))
            ? MediaSeriesCatalog(channels) : MediaSeriesCatalog([])
    }
    private var showsChannelRows: Bool {
        !(showsCategories && searchTerm.isEmpty && categories.contains(where: { !$0.name.isEmpty }))
    }
    var body: some View {
        ZStack {
            if let series { seriesPage(series) }
            else if !showsChannelRows { categoryGrid }
            else if !seriesCatalog.series.isEmpty { seriesGrid }
            else { channelList }
        }
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .navigationTitle(series != nil && onSelectChannel == nil ? "" : title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if onSelectChannel == nil || series == nil {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { TVRouteStatusButton(model: .shared) }
                        .sharedBackgroundVisibility(.hidden)
                    if let onOpenSettings {
                        ToolbarItem(placement: .topBarTrailing) { MirivoSettingsButton(action: onOpenSettings) }
                            .sharedBackgroundVisibility(.hidden)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) { TVRouteStatusButton(model: .shared) }
                    if let onOpenSettings {
                        ToolbarItem(placement: .topBarTrailing) { MirivoSettingsButton(action: onOpenSettings) }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(isPresented: $showingPlayer) {
            if onSelectChannel == nil { MediaPlayerScreen(model: .shared) }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if onSelectChannel == nil { NowPlayingBar { showingPlayer = true } }
                if showsSearch && series == nil {
                    ChannelSearchBar(text: $query, prompt: L10n.tr(!seriesCatalog.series.isEmpty ? "Dizi ara" : "Kanal veya grup ara"))
                }
            }.background(MirrorStyle.background)
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { playbackMessage != nil }, set: { if !$0 { playbackMessage = nil } })) {
            Button(L10n.tr("Tamam")) { playbackMessage = nil }
        } message: { Text(playbackMessage ?? "") }
        .onChange(of: downloads.message) { _, message in
            guard showsChannelRows, let message, let assetKey = downloads.messageAssetKey,
                  channels.contains(where: { OfflineDownloadStore.assetKey(for: $0.url) == assetKey }) else { return }
            playbackMessage = message
            downloads.clearMessage()
        }
        .task(id: episodeMetadataRequestID) {
            episodeMetadata = [:]
            guard let series, let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) else { return }
            do {
                let loaded = try await MediaMetadataLoader.episodes(source: source, channels: series.channels)
                try Task.checkCancellation()
                episodeMetadata = loaded
            } catch {
                // Names are optional. Keep the numbered, playable list visible
                // on unsupported sources, offline, or after a provider failure.
            }
        }
        .task(id: "\(canSort)|\(sortMode.rawValue)") {
            guard canSort, sortMode == .recentlyAdded, addedDates == nil else { return }
            guard let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) else {
                addedDates = [:]
                return
            }
            do {
                let dates = try await MediaMetadataLoader.addedDates(source: source, channels: channels)
                try Task.checkCancellation()
                addedDates = dates
            } catch {
                // Failed or unsupported lookups still reveal the provider list.
                // A cancelled lookup remains unresolved so revisiting can retry.
                if !Task.isCancelled { addedDates = [:] }
            }
        }
    }
    private var categoryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                NavigationLink {
                    ChannelBrowserView(channels: channels, title: L10n.tr("Tüm kanallar"), sourceID: sourceID,
                                       showsCategories: false, playlistChannels: playlistChannels ?? channels,
                                       onSelectChannel: onSelectChannel)
                } label: {
                    allChannelsRow
                }
                .buttonStyle(MirivoPressButtonStyle())
                .accessibilityLabel(L10n.tr("Tüm kanallar"))
                .accessibilityValue(String(format: L10n.tr("%d içerik"), channels.count))
                .accessibilityIdentifier("browse-all-channels")
                HStack {
                    Text(L10n.tr("Kategoriler")).font(.headline)
                    Spacer()
                    Text(categories.count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                }.accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150), spacing: 14)], spacing: 14) {
                    ForEach(categories) { category in
                        let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
                        NavigationLink {
                            ChannelBrowserView(channels: category.channels, title: name, sourceID: sourceID,
                                               showsCategories: false, playlistChannels: playlistChannels ?? channels,
                                               onSelectChannel: onSelectChannel, sortScope: "category:" + category.name)
                        } label: {
                            ChannelCategoryCard(name: name, channels: category.channels)
                        }.buttonStyle(MirivoPressButtonStyle())
                    }
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("channel-categories")
    }

    private var allChannelsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.body).foregroundStyle(MirrorStyle.accent)
                .accessibilityHidden(true)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text(L10n.tr("Tüm kanallar"))
                    .font(.body.weight(.medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(channels.count, format: .number)
                    .font(.subheadline.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MirrorStyle.hairline) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var seriesGrid: some View {
        let visibleSeries = filteredSeries
        let visibleUngrouped = ungrouped
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !searchTerm.isEmpty && visibleSeries.isEmpty && visibleUngrouped.isEmpty {
                    searchEmptyState
                }
                if !visibleSeries.isEmpty {
                    Text(String(format: L10n.tr("%d dizi"), visibleSeries.count))
                        .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 145), spacing: 18)], alignment: .leading, spacing: 24) {
                        ForEach(visibleSeries) { item in
                            NavigationLink {
                                ChannelBrowserView(channels: item.channels, title: item.title, sourceID: sourceID,
                                                   showsCategories: false, playlistChannels: item.channels,
                                                   onSelectChannel: onSelectChannel, series: item)
                            } label: { SeriesPosterCard(series: item) }
                                .buttonStyle(MirivoPressButtonStyle())
                                .accessibilityIdentifier("series-open-" + item.title)
                                .overlay(alignment: .topTrailing) {
                                    if let channel = item.artworkChannel {
                                        MediaFavoriteButton(channel: channel, sourceID: sourceID, scope: .series,
                                                            compact: true, identifier: "series-favorite-" + item.title)
                                            .padding(8)
                                    }
                                }
                        }
                    }
                }
                if !visibleUngrouped.isEmpty {
                    Text(L10n.tr("Diğer içerikler")).font(.headline).padding(.top, 8)
                    ForEach(visibleUngrouped) { channel in
                        channelRow(channel).padding(.horizontal, 16)
                            .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.accessibilityIdentifier("series-library")
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title)
            Text(L10n.tr("İçerik bulunamadı")).font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MirrorStyle.secondary)
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("channel-search-empty")
    }

    private func seriesPage(_ series: MediaSeries) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if onSelectChannel == nil, let channel = series.artworkChannel {
                        MediaDetailsView(channel: channel,
                                         source: SourceLibrary.shared.sources.first { $0.id == sourceID },
                                         series: series, playChannel: filtered.first,
                                         onPlay: { if let first = filtered.first { selectChannel(first) } })
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if series.seasons.count > 1 {
                            ScrollView(.horizontal) {
                                HStack(spacing: 24) {
                                    ForEach(series.seasons) { season in
                                        Button {
                                            selectedSeason = season.number
                                        } label: {
                                            Text(SeriesText.season(season.number))
                                                .font(.headline)
                                                .foregroundStyle(selectedSeason == season.number ? .white : MirrorStyle.secondary)
                                                .padding(.vertical, 10)
                                                .frame(minHeight: 44)
                                                .overlay(alignment: .bottom) {
                                                    Capsule().fill(selectedSeason == season.number ? MirrorStyle.accent : .clear)
                                                        .frame(height: 3)
                                                }
                                        }
                                        .buttonStyle(.plain).accessibilityIdentifier("series-season-\(season.number)")
                                        .accessibilityAddTraits(selectedSeason == season.number ? .isSelected : [])
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .overlay(alignment: .bottom) { Rectangle().fill(MirrorStyle.hairline).frame(height: 0.5) }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            if series.seasons.count == 1 {
                                Text(SeriesText.season(selectedSeason)).font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            Spacer(minLength: 8)
                            Text(String(format: L10n.tr("%d bölüm"), filtered.count))
                                .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        }.padding(.top, series.seasons.count == 1 ? 8 : 4).padding(.bottom, 2)
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { channel in
                                SeriesEpisodeRow(channel: channel, sourceID: sourceID, metadata: episodeMetadata[channel.id],
                                                 play: { selectChannel(channel) }) {
                                    if channel.isDownloadableVideo { downloadControl(for: channel, compact: true) }
                                }
                                .id(channel.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .task(id: selectedSeason) {
                let model = MirrorModel.shared
                guard onSelectChannel != nil, model.playbackSourceID == sourceID,
                      let current = model.selectedMediaChannel,
                      filtered.contains(where: { $0.id == current.id }) else { return }
                proxy.scrollTo(current.id, anchor: .center)
            }
        }
        .accessibilityIdentifier("channel-list")
    }

    private var channelList: some View {
        let visibleChannels = filtered
        return List {
            Section {
                if loadingAddedDates {
                    ProgressView(L10n.tr("Kaynak yükleniyor…"))
                        .tint(MirrorStyle.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .accessibilityIdentifier("library-sort-loading")
                } else if !searchTerm.isEmpty && visibleChannels.isEmpty {
                    searchEmptyState
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(visibleChannels) { channel in channelRow(channel) }
                }
            } header: {
                if !visibleChannels.isEmpty {
                    HStack {
                        Text(series != nil ? String(format: L10n.tr("%d bölüm"), visibleChannels.count) : String(format: L10n.tr("%d içerik"), visibleChannels.count))
                        Spacer(minLength: 8)
                        sortMenu
                    }.textCase(nil)
                }
            }
        }.listStyle(.insetGrouped).accessibilityIdentifier("channel-list")
    }
    private func channelRow(_ channel: MediaChannel) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { selectChannel(channel) } label: {
                HStack(spacing: 14) {
                    MediaArtworkView(channel: channel, cornerRadius: 12)
                        .frame(width: 56, height: channel.isLive || channel.isAudio ? 56 : 78)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(series != nil ? channel.episode.map { SeriesText.episode($0.number) } ?? channel.title : channel.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        if series != nil, let episode = channel.episode {
                            Text(episode.title ?? SeriesText.season(episode.season))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        } else if !channel.group.isEmpty {
                            Text(channel.group).font(.caption).foregroundStyle(MirrorStyle.secondary).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if channel.isLive {
                                Circle().fill(MirrorStyle.accent).frame(width: 5, height: 5)
                                Text(L10n.tr("Canlı yayın"))
                            } else if series == nil {
                                Image(systemName: channel.isAudio ? "waveform" : "film")
                                Text(channel.metadata.year ?? L10n.tr(channel.isAudio ? "Ses" : "Video"))
                            }
                        }.font(.caption2).foregroundStyle(MirrorStyle.secondary)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: MirrorStyle.controlHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(channel.title)
            HStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if channel.isLive || channel.isAudio {
                    MediaFavoriteButton(channel: channel, sourceID: sourceID, compact: true,
                                        identifier: "channel-favorite-" + channel.id)
                }
                if channel.isDownloadableVideo {
                    downloadControl(for: channel).frame(width: 44, height: 44)
                }
                Button { selectChannel(channel) } label: {
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(MirrorStyle.accent).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(channel.title)
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.padding(.vertical, 8).listRowBackground(MirrorStyle.surface)
    }
    @ViewBuilder private func downloadControl(for channel: MediaChannel, compact: Bool = false) -> some View {
        if let item = downloads.items.first(where: { $0.assetKey == OfflineDownloadStore.assetKey(for: channel.url) }) {
            if item.state == .finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MirrorStyle.accent)
                    .frame(width: 44, height: 44).accessibilityLabel(L10n.tr("İndirildi"))
            } else if item.state == .preparing || item.state == .downloading {
                Button { downloads.cancel(item) } label: {
                    Group {
                        if item.state == .preparing || item.taskIdentifier == nil {
                            ProgressView().tint(MirrorStyle.accent)
                        } else {
                            ProgressView(value: item.progress).progressViewStyle(.circular).tint(MirrorStyle.accent)
                        }
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("İndirmeyi iptal et"))
                    .accessibilityValue(L10n.tr(item.state == .preparing ? "İçerik kontrol ediliyor…" : "İndiriliyor"))
            } else if item.state == .failed {
                Button { startDownload(for: channel) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text(L10n.tr("Başarısız")).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
                    }
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(L10n.tr("İndirme başarısız. Yeniden dene."))
            } else {
                Button { startDownload(for: channel) } label: {
                    Image(systemName: compact ? "arrow.down" : "arrow.down.circle")
                        .foregroundStyle(compact ? MirrorStyle.secondary : MirrorStyle.accent)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Yeniden indir"))
            }
        } else {
            Button { startDownload(for: channel) } label: {
                Image(systemName: compact ? "arrow.down" : "arrow.down.circle").font(compact ? .body : .title3)
                    .foregroundStyle(compact ? MirrorStyle.secondary : MirrorStyle.accent)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L10n.tr("İndir"))
                .accessibilityIdentifier("download-" + OfflineDownloadStore.assetKey(for: channel.url))
        }
    }
    private func selectChannel(_ channel: MediaChannel) {
        if let onSelectChannel {
            onSelectChannel(channel)
        } else {
            let model = MirrorModel.shared
            let queue = MediaSeriesCatalog.playbackQueue(for: channel, in: playlistChannels ?? channels)
            if !model.playMedia(channel, queue: queue, sourceID: sourceID), model.requiresMembership {
                playbackMessage = model.errorMessage
                model.errorMessage = nil
            } else { showingPlayer = model.selectedMediaChannel != nil }
        }
    }
    private func startDownload(for channel: MediaChannel) {
        Task { await downloads.download(channel, sourceID: sourceID) }
    }
}

struct NowPlayingBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @ObservedObject private var history = LastPlaybackStore.shared
    let open: () -> Void
    init(model: MirrorModel? = nil, open: @escaping () -> Void) {
        let model = model ?? .shared
        self.model = model; playback = model.playback
        self.open = open
    }
    private var active: Bool { model.mediaTitle != nil && playback.hasActivePlayback }
    private var saved: LastPlaybackRecord? {
        guard !model.hidesSavedPlaybackBar, !model.broadcasting, let last = history.record,
              !last.isFinished else { return nil }
        return last
    }
    var body: some View {
        if !model.playerScreenVisible, active || saved != nil {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        if active || model.resumeLastPlayback() { open() }
                    } label: {
                        HStack(spacing: 12) {
                            if !dynamicTypeSize.isAccessibilitySize, let channel = active ? model.selectedMediaChannel : saved?.channel {
                                MediaArtworkView(channel: channel, cornerRadius: 12)
                                    .frame(width: 54, height: 54)
                                    .background {
                                        if active, playback.compatibility == nil, !playback.externalDisplayConnected {
                                            NativeVideoView(player: playback.player, playback: playback)
                                        }
                                    }
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(active ? model.mediaTitle ?? "" : saved?.title ?? "")
                                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                                HStack(spacing: 5) {
                                    if active && playback.hasRemoteVideoOutput {
                                        Image(systemName: playback.displayConnection.symbol)
                                            .foregroundStyle(MirrorStyle.accent).accessibilityIdentifier("now-playing-route")
                                    }
                                    Text(active ? (playback.hasRemoteVideoOutput ? playback.displayPlaybackStatus()
                                        : L10n.tr(playback.isPlaying ? "Şimdi oynatılıyor" : playback.state == .loading ? "Yayın hazırlanıyor" : "Yayın duraklatıldı"))
                                        : L10n.tr("İzlemeye devam et"))
                                        .lineLimit(1).accessibilityIdentifier("now-playing-output-status")
                                }.font(.caption).foregroundStyle(MirrorStyle.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier(active ? "now-playing-open" : "last-watched-open")
                    Button {
                        if active { playback.togglePlayPause() }
                        else if model.resumeLastPlayback() { open() }
                    } label: {
                        Image(systemName: active && playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .semibold)).frame(width: 46, height: 46)
                            .background(.white.opacity(0.09), in: Circle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr(active && playback.isPlaying ? "Duraklat" : "Oynat"))
                        .accessibilityIdentifier("now-playing-play-pause")
                    Button { model.stopPlayback(hideSavedPlaybackBar: true) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: 40, height: 46)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Oynatmayı durdur"))
                        .accessibilityIdentifier("now-playing-stop")
                }.padding(.horizontal, 12).padding(.vertical, 10)
                if active && playback.duration > 0 {
                    ProgressView(value: min(1, playback.currentTime / playback.duration))
                        .tint(MirrorStyle.accent).frame(height: 2).padding(.horizontal, 14)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.10)) }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal, 12).padding(.bottom, 8)
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
            possibleObservation = pip?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, let pip = self.pip else { return }
                    self.playback?.nativePictureInPictureAvailabilityChanged(pip)
                }
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
        if primary, let pip, let playback, playback.nativePiP !== pip {
            playback.nativePiP = pip
            // Registration also happens from SwiftUI's updateUIViewController.
            // Publish after that update, and ignore a source replaced meanwhile.
            Task { @MainActor [weak playback, weak pip] in
                guard let pip else { return }
                playback?.nativePictureInPictureAvailabilityChanged(pip)
            }
        }
    }
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard !stoppingForPlaybackReplacement, let playback, playback.hasActivePlayback, playback.compatibility == nil,
              playback.nativePiP === controller else { controller.stopPictureInPicture(); return }
        pipPlaybackID = playback.playbackID
        prepareForPictureInPicture()
        startingPiP = true
        playback.retainedPiPController = self
        playback.pictureInPictureAvailabilityChanged()
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
        if playback?.nativePiP === controller {
            setPrimary(true)
            playback?.nativePictureInPictureAvailabilityChanged(controller)
        }
        playback?.pictureInPictureSourceStopped(self)
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
        if playback?.nativePiP === controller {
            setPrimary(true)
            playback?.nativePictureInPictureAvailabilityChanged(controller)
        }
        playback?.pictureInPictureSourceStopped(self)
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
        if playback.hasRemoteVideoOutput && role != .external {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: playback.displayConnection.symbol).accessibilityHidden(true)
                    Text(playback.displayConnection.destinationName).accessibilityIdentifier("player-output-destination")
                }.font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                Text(playback.displayPlaybackStatus())
                    .font(.caption2).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityIdentifier("player-output-status")
            }.padding(.horizontal, 48).padding(.top, 8)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.black)
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
                            .disabled(!playback.canStartPictureInPicture)
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
struct PlaybackTimelineView: View {
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

struct PlaybackCaptureGuard: ViewModifier {
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    init(model: MirrorModel) { self.model = model; playback = model.playback }
    private var shouldBlock: Bool {
        // Scene capture also describes legitimate mirroring. Those routes keep
        // playing; sample-buffer protection covers their decoded picture.
        Self.blocksPlayback(captured: isSceneCaptured, broadcasting: model.broadcasting,
                            remoteOutput: playback.hasRemoteVideoOutput || playback.externalDisplayConnected,
                            audio: model.selectedMediaChannel?.isAudio == true)
    }
    static func blocksPlayback(captured: Bool, broadcasting: Bool, remoteOutput: Bool, audio: Bool) -> Bool {
        captured && !broadcasting && !remoteOutput && !audio
    }
    func body(content: Content) -> some View {
        content.onChange(of: shouldBlock, initial: true) { _, blocked in
            playback.setScreenCaptureBlocked(blocked)
        }.onChange(of: model.broadcasting, initial: true) { _, active in
            playback.setBroadcastCaptureActive(active)
        }
    }
}

struct MediaPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @State private var largeControls = false
    @State private var fullscreen = false
    @State private var videoDisplayMode = PlayerVideoDisplayMode.normal
    @State private var automaticLandscapeSuppressed = false
    @State private var playerVisible = false
    @State private var landscapeLayout = false
    @State private var orientationTransitionTask: Task<Void, Never>?
    init(model: MirrorModel) { self.model = model; playback = model.playback }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: fullscreen ? 0 : 20) {
                if playback.hasActivePlayback {
                    // Keep this surface mounted in both sizes. A cover used to
                    // remove it and mount another decoder surface during the fade.
                    ZStack {
                        if playback.hasRemoteVideoOutput {
                            RemotePlaybackPanel(model: model)
                        } else if model.selectedMediaChannel?.isAudio == true {
                            ZStack {
                                MirrorStyle.surface
                                Image(systemName: "waveform").font(.system(size: 54, weight: .light))
                                    .foregroundStyle(MirrorStyle.accent)
                            }
                        } else {
                            MediaVideoView(playback: playback, role: .inline,
                                           displayMode: videoDisplayMode.effective(fullscreen: fullscreen,
                                               landscape: geometry.size.width > geometry.size.height))
                        }
                        if !playback.hasRemoteVideoOutput {
                            PlayerChrome(model: model, fullscreen: $fullscreen, largeControls: $largeControls,
                                     displayMode: $videoDisplayMode, changeFullscreen: changeFullscreen,
                                     exitToPortrait: exitFullscreenToPortrait)
                            .accessibilityHidden(playback.screenCaptureBlocked)
                        }
                        if playback.screenCaptureBlocked {
                            Color.black
                            Label(L10n.tr("Devam etmek için ekran kaydını durdur."), systemImage: "record.circle")
                                .font(.subheadline).multilineTextAlignment(.center).padding(24)
                                .accessibilityIdentifier("player-capture-blocked")
                        }
                    }
                    .frame(minHeight: playback.hasRemoteVideoOutput ? 210 : nil)
                    .frame(height: playback.hasRemoteVideoOutput ? nil : fullscreen ? geometry.size.height : max(0, min(geometry.size.width - 40, 720)) * 9 / 16)
                    .background(playback.hasRemoteVideoOutput ? Color.clear : Color.black)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("player-video")
                    .accessibilityValue(L10n.tr(videoDisplayMode.effective(fullscreen: fullscreen,
                        landscape: geometry.size.width > geometry.size.height).title))
                    // A fixed rectangular source avoids animating a second
                    // corner mask while AVKit animates its own PiP window.
                    .clipped()
                    .padding(.horizontal, fullscreen ? 0 : 20)
                }
                if !fullscreen {
                    ScrollView { playerDetails.padding(.bottom, 24) }
                        .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.top, fullscreen ? 0 : 20)
            .frame(maxWidth: fullscreen ? .infinity : 760).frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear {
                landscapeLayout = geometry.size.width > geometry.size.height
                if landscapeLayout && playback.hasActivePlayback && !automaticLandscapeSuppressed { setFullscreen(true) }
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
            playerVisible = true
            automaticLandscapeSuppressed = false
            updateOrientationPolicy()
            if landscapeLayout && playback.hasActivePlayback { setFullscreen(true) }
            model.playerVisibilityChanged(true)
        }
        .onDisappear {
            playerVisible = false
            orientationTransitionTask?.cancel()
            PlayerOrientationPolicy.update(playerVisible: false, allowsLandscape: false)
            model.playerVisibilityChanged(false)
        }
        .onChange(of: playback.tvDevice != nil) { _, connected in
            updateOrientationPolicy()
            if connected { leaveFullscreenAutomatically() }
        }
        .onChange(of: playback.externalDisplayConnected) { _, _ in
            updateOrientationPolicy()
            if playback.externalDisplayConnected { leaveFullscreenAutomatically() }
        }
        .onChange(of: playback.externalPlaybackActive) { _, _ in
            updateOrientationPolicy()
            if playback.externalPlaybackActive { leaveFullscreenAutomatically() }
        }
        .onChange(of: playback.playsOnPhone) { _, _ in
            updateOrientationPolicy()
            if playback.hasRemoteVideoOutput { leaveFullscreenAutomatically() }
        }
        .onChange(of: model.selectedMediaChannel) { _, channel in
            videoDisplayMode = .normal
            if channel == nil {
                playerVisible = false
                orientationTransitionTask?.cancel()
                PlayerOrientationPolicy.update(playerVisible: false, allowsLandscape: false)
                dismiss()
            }
        }
        .onChange(of: playback.state) { _, state in
            if state == .failed || state == .idle { leaveFullscreenAutomatically() }
        }
        .onChange(of: playback.hasActivePlayback) { _, active in
            updateOrientationPolicy()
            if active && landscapeLayout && playerVisible && !automaticLandscapeSuppressed { setFullscreen(true) }
        }
        .task(id: model.selectedMediaChannel?.id) { await model.restorePlaybackQueueFromSource() }
        .alert(BrandIdentity.name, isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L10n.tr("Tamam")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var playerDetails: some View {
        VStack(spacing: 20) {
            if model.requiresMembership {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L10n.tr("Mirivo Pro"), systemImage: "play.rectangle").font(.headline)
                    Text(L10n.tr("Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir.")).font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                    Button { model.presentMembershipOffer() } label: {
                        Label(L10n.tr("Mirivo Pro"), systemImage: "crown").frame(maxWidth: .infinity)
                    }.buttonStyle(MirivoButtonStyle(prominent: true)).accessibilityIdentifier("membership-pro")
                }.padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            } else if let failure = model.mediaErrorMessage, !playback.hasActivePlayback {
                ContentUnavailableView {
                    Label(L10n.tr("Yayın tamamlanamadı"), systemImage: "exclamationmark.triangle")
                } description: { Text(failure) }
            }
            if !model.requiresMembership, !playback.hasActivePlayback, model.selectedMediaChannel != nil {
                Button(L10n.tr("Yeniden dene")) { model.retryMedia() }.buttonStyle(MirivoButtonStyle(prominent: true))
            }
            if playback.hasActivePlayback {
                VStack(spacing: 20) {
                    PlaybackTimelineView(playback: playback).id(model.selectedMediaChannel?.id)
                    if playback.playsOnPhone && playback.externalDisplayConnected {
                        Button { model.returnToDisplay() } label: {
                            Label(L10n.tr("Bu ekranda oynat"), systemImage: playback.displayConnection.symbol)
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("player-return-to-display")
                    }
                    TVConnectionButton(model: model)
                    if playback.tvName != nil && model.selectedMediaChannel?.url.isFileURL == true {
                        Label(L10n.tr("TV’ye bu iPhone’dan aktarılıyor. Mirivo’yu açık tut."), systemImage: "iphone.radiowaves.left.and.right")
                            .font(.footnote).foregroundStyle(MirrorStyle.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(role: .destructive) { model.stopPlayback(hideSavedPlaybackBar: true) } label: {
                        Label(L10n.tr("Oynatmayı durdur"), systemImage: "stop.circle").font(.subheadline).frame(minHeight: 44)
                    }.accessibilityIdentifier("stop-player-playback")
                }.padding(20).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
            }
            if let channel = model.selectedMediaChannel, !channel.isLive {
                MediaDetailsView(channel: channel, source: model.playbackSource)
                    .id(channel.id)
            }
        }.padding(.horizontal, 20)
    }
    private func setFullscreen(_ value: Bool) {
        changeFullscreen(value, landscape: landscapeLayout)
    }

    private func changeFullscreen(_ value: Bool, landscape: Bool) {
        guard playerVisible, model.selectedMediaChannel != nil, !value || fullscreenAllowed else { return }
        if value {
            automaticLandscapeSuppressed = false
        } else {
            automaticLandscapeSuppressed = PlayerFullscreenRotationPolicy.suppressAutomaticLandscape(
                fullscreen: fullscreen, landscape: landscape)
        }
        updateOrientationPolicy()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { fullscreen = value }
    }

    private func leaveFullscreenAutomatically() {
        // Route changes and playback failures do not suppress later rotations.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { fullscreen = false }
        updateOrientationPolicy()
    }

    private func exitFullscreenToPortrait(_ landscape: Bool) {
        changeFullscreen(false, landscape: landscape)
    }

    private var fullscreenAllowed: Bool {
        playback.hasActivePlayback && !playback.hasRemoteVideoOutput
    }

    private func updateOrientationPolicy() {
        guard playerVisible, model.selectedMediaChannel != nil else { return }
        PlayerOrientationPolicy.update(playerVisible: true, allowsLandscape: fullscreenAllowed && !automaticLandscapeSuppressed)
    }

    private func scheduleOrientationAdaptation(for size: CGSize) {
        orientationTransitionTask?.cancel()
        orientationTransitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return }
            guard playerVisible, model.selectedMediaChannel != nil else { return }
            let isLandscape = size.width > size.height
            guard isLandscape != landscapeLayout else { return }
            landscapeLayout = isLandscape
            if !isLandscape { return }
            guard !automaticLandscapeSuppressed else { return }
            // Landscape rotation enters fullscreen; portrait rotation keeps
            // the current fullscreen choice.
            if playback.hasActivePlayback && fullscreenAllowed { setFullscreen(true) }
        }
    }
}

/// Standalone host used by external previews and rotation regression tests.
struct RemotePlaybackPanel: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @AppStorage("player.externalVideoDisplayMode") private var displayMode = PlayerVideoDisplayMode.normal
    @State private var showingChannels = false
    @State private var showingMediaChoices = false
    init(model: MirrorModel) { self.model = model; playback = model.playback }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: playback.displayConnection.symbol).font(.title2).foregroundStyle(MirrorStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.displayConnection.destinationName).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("player-output-destination")
                    Text(playback.displayPlaybackStatus()).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("player-output-status")
                }
                Spacer(minLength: 0)
                Button { showingMediaChoices = true } label: {
                    Image(systemName: playback.showsVideoQuality ? "slider.horizontal.3" : "captions.bubble").font(.title3).frame(width: 44, height: 48)
                }
                .accessibilityLabel(L10n.tr(playback.showsVideoQuality ? "Oynatma seçenekleri" : "Ses ve altyazı")).accessibilityIdentifier("player-media-options")
                if let channel = model.selectedMediaChannel {
                    MediaFavoriteButton(channel: channel, sourceID: model.playbackSourceID)
                }
            }
            HStack(spacing: 12) {
                Button { model.playOnPhone() } label: {
                    Label(L10n.tr("Telefonda oynat"), systemImage: "iphone")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white, in: Capsule()).foregroundStyle(.black)
                }.accessibilityIdentifier("player-play-on-phone")
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 52, height: 48)
                        .background(.white.opacity(0.12), in: Capsule())
                }.accessibilityLabel(L10n.tr(playback.isPlaying ? "Duraklat" : "Oynat"))
                    .accessibilityIdentifier("player-play-pause")
            }
            HStack(spacing: 16) {
                Button { showingChannels = true } label: {
                    Label(L10n.tr(model.selectedMediaChannel?.episode != nil ? "Bölümler" : "Kanallar"), systemImage: "list.bullet")
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("player-channel-picker")
                Spacer(minLength: 0)
                if model.playbackQueue.count > 1 {
                    Button { model.switchChannel(-1) } label: {
                        Image(systemName: "backward.end.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                        .disabled(model.adjacentChannel(-1) == nil).accessibilityLabel(L10n.tr("Önceki bölüm")).accessibilityIdentifier("previous-episode")
                    Button { model.switchChannel(1) } label: {
                        Image(systemName: "forward.end.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                        .disabled(model.adjacentChannel(1) == nil).accessibilityLabel(L10n.tr("Sonraki bölüm")).accessibilityIdentifier("next-episode")
                }
                if playback.canAdjustRemoteVideoDisplayMode {
                    Menu {
                        Button(L10n.tr("Sığdır")) { displayMode = .normal }
                        Button(L10n.tr("Uzat")) { displayMode = .fillScreen }
                    } label: { Image(systemName: "aspectratio").frame(width: 44, height: 44) }
                        .accessibilityLabel(L10n.tr("Görüntü boyutu")).accessibilityIdentifier("player-display-mode")
                }
            }.font(.subheadline.weight(.medium))
        }
        .padding(18).foregroundStyle(.white).buttonStyle(.plain)
        .background {
            // System-managed video routes still need a mounted native layer.
            if playback.compatibility == nil && !playback.externalDisplayConnected {
                NativeVideoView(player: playback.player, playback: playback)
            }
            RoundedRectangle(cornerRadius: 20).fill(MirrorStyle.surface)
        }
        .sheet(isPresented: $showingChannels) { PlaybackQueueSheet(model: model) }
        .sheet(isPresented: $showingMediaChoices) { PlayerMediaChoicesView(playback: playback) }
    }
}

struct FullscreenPlayerView: View {
    var largeControls: Bool = true
    @ObservedObject var model: MirrorModel
    let close: () -> Void
    @State private var videoDisplayMode = PlayerVideoDisplayMode.normal
    var body: some View {
        GeometryReader { geometry in
            MediaVideoView(playback: model.playback, role: .fullscreen,
                           displayMode: videoDisplayMode.effective(fullscreen: true,
                               landscape: geometry.size.width > geometry.size.height))
                .overlay {
                    PlayerChrome(model: model, fullscreen: .constant(true), largeControls: .constant(largeControls),
                                 displayMode: $videoDisplayMode, changeFullscreen: { value, _ in if !value { close() } },
                                 exitToPortrait: { _ in close() })
                }
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
    let changeFullscreen: (Bool, Bool) -> Void
    let exitToPortrait: (Bool) -> Void
    @State private var controlsVisible = true
    @State private var controlsLocked = false
    @State private var showingTVs = false
    @State private var showingChannels = false
    @State private var showingMediaChoices = false
    @State private var showingOptions = false
    @State private var showingDisplayModes = false
    @State private var isScrubbing = false
    @State private var timelineFrame: CGRect = .zero
    @State private var hideTask: Task<Void, Never>?
    @State private var awakeLease: UUID?
    @State private var screenInsets = EdgeInsets()
    @State private var seekFeedback: Int?
    @State private var seekFeedbackPulse = 0
    @State private var feedbackTask: Task<Void, Never>?
    @State private var showingEdgeGestureIntro = false
    @State private var gestureAdjustment: PlayerGestureAdjustment?
    @State private var gestureAdjustmentValue: CGFloat = 0
    @State private var adjustmentHideTask: Task<Void, Never>?

    init(model: MirrorModel, fullscreen: Binding<Bool>, largeControls: Binding<Bool>, displayMode: Binding<PlayerVideoDisplayMode>,
         changeFullscreen: @escaping (Bool, Bool) -> Void, exitToPortrait: @escaping (Bool) -> Void) {
        self.model = model; playback = model.playback
        _fullscreen = fullscreen; _largeControls = largeControls; _displayMode = displayMode
        self.changeFullscreen = changeFullscreen
        self.exitToPortrait = exitToPortrait
    }
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let fullscreenExitEnabled = fullscreen &&
                !controlsLocked && !showingEdgeGestureIntro && !showingTVs && !showingChannels &&
                !showingMediaChoices && !showingOptions && !showingDisplayModes
            ZStack {
                PlayerGestureSurface(locked: controlsLocked || showingEdgeGestureIntro,
                                     fullscreen: fullscreen,
                                     landscape: isLandscape,
                                     singleTap: toggleControls, doubleTap: skip,
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
                                    .onGeometryChange(for: CGRect.self) { proxy in
                                        proxy.frame(in: .named("player-chrome"))
                                    } action: { timelineFrame = $0 }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(name: "player-chrome")
            // Both orientations use the same drag and velocity thresholds,
            // including drags starting on playback buttons. Seeking and the
            // landscape edge adjustments retain their own gestures.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .named("player-chrome"))
                    .onEnded { value in
                        guard fullscreenExitEnabled, fullscreen, !isScrubbing,
                              !(controlsVisible && timelineFrame.contains(value.startLocation)),
                              !isLandscape || PlayerGestureAdjustment.landscapeEdge(
                                at: value.startLocation.x, width: geometry.size.width) == nil,
                              PlayerFullscreenExitGesture.shouldExit(translation: value.translation, velocity: value.velocity) else { return }
                        exitToPortrait(isLandscape)
                    },
                including: fullscreenExitEnabled ? .all : .subviews
            )
            .onAppear {
                updateAwakeLease(); scheduleHide()
                updateEdgeGestureIntro(size: geometry.size)
            }
            .onChange(of: fullscreen) { _, _ in
                showingOptions = false; showingDisplayModes = false; clearSeekFeedback(); updateAwakeLease(); revealControls()
                updateEdgeGestureIntro(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in updateEdgeGestureIntro(size: size) }
            .onChange(of: edgeGestureIntroShown) { _, _ in updateEdgeGestureIntro(size: geometry.size) }
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .sheet(isPresented: $showingTVs) { DisplayConnectionView(model: model) }
        .sheet(isPresented: $showingChannels) { PlaybackQueueSheet(model: model) }
        .sheet(isPresented: $showingMediaChoices) { PlayerMediaChoicesView(playback: playback) }
        .onDisappear {
            hideTask?.cancel(); clearSeekFeedback(); adjustmentHideTask?.cancel()
            MediaScreenAwake.release(awakeLease)
        }
        .onChange(of: playback.isPlaying) { _, _ in revealControls() }
        .onChange(of: controlsLocked) { _, _ in clearSeekFeedback(); revealControls() }
        .onChange(of: showingTVs) { _, _ in revealControls() }
        .onChange(of: showingChannels) { _, _ in revealControls() }
        .onChange(of: showingMediaChoices) { _, _ in revealControls() }
        .onChange(of: showingOptions) { _, _ in revealControls() }
        .onChange(of: showingDisplayModes) { _, _ in revealControls() }
        .onChange(of: model.selectedMediaChannel?.id) { _, _ in
            showingOptions = false; showingDisplayModes = false; showingMediaChoices = false; clearSeekFeedback(); revealControls()
        }
    }
    private func header(isLandscape: Bool) -> some View {
        Group {
            if controlsLocked {
                HStack {
                    Spacer(minLength: 0)
                    headerButton("lock.open.fill", label: "Kilidi aç", id: "unlock-player-controls") { controlsLocked = false }
                        .background(.ultraThinMaterial, in: Capsule())
                }
            } else if controlsVisible {
                if fullscreen {
                    HStack(alignment: .center, spacing: 12) {
                        headerTitle
                        headerActions(isLandscape: isLandscape)
                            .layoutPriority(1)
                    }
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        headerActions(isLandscape: isLandscape)
                    }
                }
            }
        }
        .padding(.horizontal, fullscreen ? 20 : 8)
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            if largeControls {
                Text(L10n.tr("Araç modu"))
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            }
            Text(model.mediaTitle ?? BrandIdentity.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func headerActions(isLandscape: Bool) -> some View {
        HStack(spacing: 0) {
            if let channel = model.selectedMediaChannel {
                MediaFavoriteButton(channel: channel, sourceID: model.playbackSourceID, compact: true, playerChrome: true)
            }
            headerButton(playback.showsVideoQuality ? "slider.horizontal.3" : "captions.bubble",
                         label: playback.showsVideoQuality ? "Oynatma seçenekleri" : "Ses ve altyazı",
                         id: "player-media-options") { showingMediaChoices = true }
            if fullscreen {
                TVConnectionButton(model: model, compact: true, playerChrome: true, presentPicker: {
                    showingTVs = true
                    hideTask?.cancel()
                })
                Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18).padding(.horizontal, 3)
                headerButton("ellipsis", label: "Video seçenekleri", id: "player-options") { showingOptions.toggle() }
                    .popover(isPresented: $showingOptions, arrowEdge: .top) {
                        playerOptions(isLandscape: isLandscape).presentationCompactAdaptation(.popover)
                    }
            } else if !playback.hasRemoteVideoOutput {
                headerButton("arrow.up.left.and.arrow.down.right", label: "Tam ekran", id: "player-fullscreen") {
                    largeControls = false; changeFullscreen(true, isLandscape)
                }
            }
        }
        .padding(2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private func headerButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); revealControls() } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.tr(label)).accessibilityIdentifier(id)
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
            optionButton("Durdur", icon: "stop.fill", destructive: true) { model.stopPlayback(hideSavedPlaybackBar: true) }
        }.padding(8).frame(minWidth: 240)
            .accessibilityElement(children: .contain).accessibilityIdentifier("player-options-popover")
            .task { @MainActor in
                // The popover owns its timer so presentation changes on the
                // player cannot cancel it while the menu is still visible.
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard !Task.isCancelled, !UIAccessibility.isVoiceOverRunning else { return }
                showingOptions = false
            }
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
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var transportControls: some View {
        HStack(spacing: hasEpisodeNavigation ? (fullscreen ? 14 : 8) : (fullscreen ? 28 : 20)) {
            if hasEpisodeNavigation {
                iconButton("backward.end.fill", label: "Önceki bölüm", id: "previous-episode") { model.switchChannel(-1) }
                    .disabled(model.adjacentChannel(-1) == nil)
            }
            if playback.canSeek && (!fullscreen || !largeControls) {
                iconButton("gobackward.10", label: "10 saniye geri", id: "skip-backward") { skip(-10) }
            } else if model.playbackQueue.count > 1 && !hasEpisodeNavigation {
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
            } else if model.playbackQueue.count > 1 && !hasEpisodeNavigation {
                iconButton("forward.end.fill", label: "Sonraki", id: "next-channel") { model.switchChannel(1) }
                    .disabled(model.adjacentChannel(1) == nil)
            }
            if hasEpisodeNavigation {
                iconButton("forward.end.fill", label: "Sonraki bölüm", id: "next-episode") { model.switchChannel(1) }
                    .disabled(model.adjacentChannel(1) == nil)
            }
        }
    }
    private var hasEpisodeNavigation: Bool {
        model.selectedMediaChannel?.episode != nil && model.playbackQueue.count > 1
    }
    private func modeActions(compact: Bool, vertical: Bool) -> some View {
        HStack(spacing: vertical ? 5 : 8) {
            if playback.hasRemoteVideoOutput {
                modeButton("Bağlantı", icon: playback.displayConnection.symbol, id: "player-display-connection",
                           compact: compact, vertical: vertical, selected: false) { showingTVs = true }
                if playback.canAdjustRemoteVideoDisplayMode {
                    modeButton("Görüntü boyutu", icon: "aspectratio", id: "player-display-mode", compact: compact,
                               vertical: vertical, selected: false) {
                        showingDisplayModes = true; hideTask?.cancel()
                    }
                    .popover(isPresented: $showingDisplayModes, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(PlayerVideoDisplayMode.allCases) { mode in
                                optionButton(mode.title, icon: mode.icon, selected: displayMode == mode) {
                                    displayMode = mode; showingDisplayModes = false
                                }
                            }
                        }.padding(8).frame(minWidth: 240)
                            .presentationCompactAdaptation(.popover)
                            .accessibilityIdentifier("player-display-mode-popover")
                            .task {
                                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                                guard !UIAccessibility.isVoiceOverRunning else { return }
                                showingDisplayModes = false
                            }
                            .onDisappear { revealControls() }
                    }
                }
            } else {
                modeButton("Araç modu", icon: "car.side", id: "player-large-controls", compact: compact,
                           vertical: vertical, selected: fullscreen && largeControls) {
                    largeControls = true; changeFullscreen(true, !vertical); revealControls()
                }
                if fullscreen {
                    modeButton(largeControls ? "Tam ekran" : "Tam ekrandan çık", icon: !largeControls ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               id: "player-fullscreen", compact: true, vertical: vertical, selected: !largeControls) {
                        if !largeControls { changeFullscreen(false, !vertical) }
                        else { largeControls = false; changeFullscreen(true, !vertical) }
                        revealControls()
                    }
                    .frame(width: vertical ? 76 : nil)
                } else {
                    modeButton("Picture in Picture", icon: "pip.enter", id: "player-pip", compact: compact, vertical: vertical, selected: false) {
                        playback.startPictureInPicture(); revealControls()
                    }.disabled(!playback.canStartPictureInPicture)
                }
            }
            modeButton(model.selectedMediaChannel?.isLive == true ? "Kanallar" : "Oynatma listesi", icon: "list.bullet", id: "player-channel-picker", compact: compact, vertical: vertical, selected: false) {
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
        guard fullscreen, !controlsLocked, !showingOptions, !showingDisplayModes, !showingEdgeGestureIntro else { return }
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
        guard controlsVisible, playback.isPlaying, !controlsLocked, !showingTVs, !showingChannels, !showingMediaChoices, !showingOptions, !showingDisplayModes, !isScrubbing,
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
    private func updateEdgeGestureIntro(size: CGSize) {
        guard fullscreen, size.width > size.height else {
            showingEdgeGestureIntro = false
            return
        }
        if !edgeGestureIntroShown { showingEdgeGestureIntro = true }
    }
}

private struct PlayerMediaChoicesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var playback: PlaybackController
    var body: some View {
        NavigationStack {
            List {
                if playback.showsVideoQuality {
                    Section {
                        Picker(L10n.tr("Görüntü kalitesi"), selection: Binding(
                            get: { playback.selectedVideoQualityID },
                            set: { playback.selectVideoQuality($0) }
                        )) {
                            Text(L10n.tr("Otomatik")).tag(String?.none)
                            ForEach(playback.videoQualities) { quality in
                                Text(String(format: L10n.tr("En fazla %@"), quality.title)).tag(Optional(quality.id))
                            }
                        }
                        .pickerStyle(.menu).listRowBackground(MirrorStyle.surface)
                        .accessibilityIdentifier("player-video-quality")
                    } footer: {
                        Text(L10n.tr("Bağlantı hızına göre seçtiğin çözünürlüğün altına inebilir. Kalite değişimi kısa bir süre alabilir."))
                    }
                }
                Section(L10n.tr("Ses dili")) {
                    if playback.audioTracks.isEmpty {
                        Text(L10n.tr("Bu yayında seçilebilir ses parçası yok."))
                            .foregroundStyle(.secondary).listRowBackground(MirrorStyle.surface)
                            .accessibilityIdentifier("audio-tracks-empty")
                    } else {
                        ForEach(playback.audioTracks) { track in
                            choice(track.title, selected: track.isSelected, id: "audio-track-\(track.id)") {
                                playback.selectAudioTrack(track.id)
                            }
                        }
                    }
                }
                Section(L10n.tr("Altyazı")) {
                    if playback.subtitleTracks.isEmpty {
                        Text(L10n.tr("Bu yayında altyazı bulunmuyor."))
                            .foregroundStyle(.secondary).listRowBackground(MirrorStyle.surface)
                            .accessibilityIdentifier("subtitle-tracks-empty")
                    } else {
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
                if playback.canAdjustSubtitlePosition {
                    Section {
                        Picker(L10n.tr("Altyazı konumu"), selection: $playback.subtitlePosition) {
                            ForEach(PlayerSubtitlePosition.allCases) { position in
                                Text(L10n.tr(position.title)).tag(position)
                            }
                        }
                        .listRowBackground(MirrorStyle.surface)
                        .accessibilityIdentifier("subtitle-position")
                    } footer: {
                        Text(L10n.tr("Metin altyazılarında uygulanır. Videoya gömülü yazılar taşınamaz."))
                    }
                }
            }
            .scrollContentBackground(.hidden).background(MirrorStyle.background)
            .navigationTitle(L10n.tr(playback.showsVideoQuality ? "Oynatma seçenekleri" : "Ses ve altyazı")).navigationBarTitleDisplayMode(.inline)
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

/// Single taps wait for double taps on the clear video surface.
/// Landscape edge pans and pinch stay on the video surface. Fullscreen exit
/// drags are observed by the enclosing chrome, including its playback buttons.
private struct PlayerGestureSurface: UIViewRepresentable {
    var locked: Bool
    var fullscreen: Bool
    var landscape: Bool
    var singleTap: () -> Void
    var doubleTap: (Int) -> Void
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
            let isPan = recognizer is UIPanGestureRecognizer
            let landscapeOnly = isPan || recognizer is UIPinchGestureRecognizer
            let enabled = !locked && (!landscapeOnly || (fullscreen && landscape))
            if recognizer.isEnabled != enabled { recognizer.isEnabled = enabled }
        }
    }
    @MainActor final class GestureView: UIView {
        var insetsChanged: ((EdgeInsets) -> Void)?
        private var reportedInsets: EdgeInsets?
        private let volumeView = MPVolumeView(frame: CGRect(x: -220, y: 0, width: 200, height: 40))
        func installVolumeView() {
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
        private enum PanMode: Equatable { case none, volume, brightness }
        init(_ parent: PlayerGestureSurface) { self.parent = parent }
        @objc func tap() { parent.singleTap() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            parent.doubleTap(gesture.location(in: view).x < view.bounds.midX ? -10 : 10)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard parent.fullscreen, parent.landscape, !parent.locked else { return }
            if gesture.state == .ended { parent.pinchEnded(gesture.scale) }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            guard parent.fullscreen, parent.landscape, !parent.locked, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            let startX = pan.location(in: view).x - pan.translation(in: view).x
            // Center drags belong to the enclosing fullscreen exit gesture.
            return abs(velocity.y) > abs(velocity.x) &&
                PlayerGestureAdjustment.landscapeEdge(at: startX, width: view.bounds.width) != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPanGestureRecognizer || gestureRecognizer is UIPinchGestureRecognizer) &&
                (otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer)
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard parent.fullscreen, parent.landscape, let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                let startX = gesture.location(in: view).x - translation.x
                switch PlayerGestureAdjustment.landscapeEdge(at: startX, width: view.bounds.width) {
                case .volume: panMode = .volume
                case .brightness: panMode = .brightness
                case nil: panMode = .none
                }
                lastPanY = translation.y
            case .changed:
                let delta = (lastPanY - translation.y) / max(view.bounds.height, 1)
                lastPanY = translation.y
                if delta != 0 {
                    switch panMode {
                    case .volume:
                        if let value = (view as? GestureView)?.adjustVolume(by: delta) { parent.adjustVolume(value) }
                    case .brightness: parent.adjustBrightness(delta)
                    case .none: break
                    }
                }
            case .ended, .cancelled, .failed:
                panMode = .none
            default: break
            }
        }
    }
}

/// A channel switcher opens directly on the current station, without sending
/// the viewer back through the source library's category cards.
private struct LiveChannelPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let channels: [MediaChannel]
    let currentChannelID: String?
    let sourceID: UUID?
    let select: (MediaChannel) -> Void
    let expand: () -> Void
    private let categories: [MediaChannelCategory]
    @State private var query = ""
    @State private var selectedCategory: String?

    init(channels: [MediaChannel], currentChannelID: String?, sourceID: UUID?, select: @escaping (MediaChannel) -> Void,
         expand: @escaping () -> Void) {
        let liveChannels = channels.filter(\.isLive)
        self.channels = liveChannels
        self.currentChannelID = currentChannelID
        self.sourceID = sourceID
        self.select = select
        self.expand = expand
        categories = MediaChannelCategory.group(liveChannels)
    }

    private var filtered: [MediaChannel] {
        let scoped = selectedCategory.flatMap { name in categories.first { $0.id == name }?.channels } ?? channels
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return scoped }
        return scoped.filter { $0.title.localizedStandardContains(term) || $0.group.localizedStandardContains(term) }
    }

    var body: some View {
        let visibleChannels = filtered
        VStack(spacing: 0) {
            ChannelSearchBar(text: $query, prompt: L10n.tr("Kanal veya grup ara")) { editing in
                if editing { expand() }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Menu {
                    Button { selectedCategory = nil } label: {
                        if selectedCategory == nil { Label(L10n.tr("Tüm kanallar"), systemImage: "checkmark") }
                        else { Text(L10n.tr("Tüm kanallar")) }
                    }
                    ForEach(categories) { category in
                        Button { selectedCategory = category.id } label: {
                            if selectedCategory == category.id {
                                Label(category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(selectedCategory.map { $0.isEmpty ? L10n.tr("Diğer kanallar") : $0 } ?? L10n.tr("Tüm kanallar"))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.tr("Kategoriler"))
                .accessibilityValue(selectedCategory.map { $0.isEmpty ? L10n.tr("Diğer kanallar") : $0 } ?? L10n.tr("Tüm kanallar"))
                .accessibilityIdentifier("live-channel-category")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(String(format: L10n.tr("%d içerik"), visibleChannels.count))
                    .font(.caption.monospacedDigit()).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityIdentifier("live-channel-count")
            }
            .padding(.horizontal, 24).padding(.bottom, 8)
            Divider().overlay(MirrorStyle.hairline)
            ScrollViewReader { proxy in
                List {
                    if visibleChannels.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .accessibilityIdentifier("channel-search-empty")
                    } else {
                        ForEach(visibleChannels) { channel in
                            channelRow(channel)
                                .id(channel.id)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("live-channel-list")
                .onAppear { scrollToCurrent(using: proxy, in: visibleChannels) }
                .onChange(of: channels) { _, _ in scrollToCurrent(using: proxy, in: visibleChannels) }
                .onChange(of: selectedCategory) { _, _ in scrollToCurrent(using: proxy, in: visibleChannels) }
            }
        }
        .background(MirrorStyle.background)
        .onAppear { if dynamicTypeSize.isAccessibilitySize { expand() } }
    }

    private func scrollToCurrent(using proxy: ScrollViewProxy, in channels: [MediaChannel]) {
        if let current = channels.first(where: { $0.id == currentChannelID }) {
            proxy.scrollTo(current.id, anchor: .center)
        } else if let first = channels.first {
            proxy.scrollTo(first.id, anchor: .top)
        }
    }

    private func channelRow(_ channel: MediaChannel) -> some View {
        let isCurrent = channel.id == currentChannelID
        return HStack(spacing: 8) {
            Button { select(channel) } label: {
                HStack(spacing: 12) {
                    MediaArtworkView(channel: channel, cornerRadius: 10)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(isCurrent ? MirrorStyle.accent : .white)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        if isCurrent {
                            Text(L10n.tr("Şimdi oynatılıyor")).foregroundStyle(MirrorStyle.accent)
                                .font(.caption)
                        } else if !channel.group.isEmpty {
                            Text(channel.group).font(.caption).foregroundStyle(MirrorStyle.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: isCurrent ? 16 : 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? MirrorStyle.accent : MirrorStyle.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(channel.title)
            .accessibilityValue(isCurrent ? L10n.tr("Şimdi oynatılıyor") : channel.group)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityIdentifier("live-channel-" + channel.id)
            MediaFavoriteButton(channel: channel, sourceID: sourceID, compact: true,
                                identifier: "live-channel-favorite-" + channel.id)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
        .listRowBackground(isCurrent ? MirrorStyle.accent.opacity(0.10) : Color.clear)
        .listRowSeparatorTint(MirrorStyle.hairline)
    }
}

private struct PlaybackQueueSheet: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var detent: PresentationDetent
    private let isLive: Bool
    init(model: MirrorModel) {
        self.model = model
        isLive = model.selectedMediaChannel?.isLive == true
        _detent = State(initialValue: .fraction(0.75))
    }
    private var currentSeries: MediaSeries? {
        guard let channel = model.selectedMediaChannel, channel.episode != nil else { return nil }
        return MediaSeriesCatalog(model.playbackQueue).series.first { $0.channels.contains { $0.id == channel.id } }
    }
    var body: some View {
        NavigationStack {
            if isLive {
                LiveChannelPicker(channels: model.playbackQueue, currentChannelID: model.selectedMediaChannel?.id,
                                  sourceID: model.playbackSourceID,
                                  select: selectChannel, expand: { detent = .large })
                    .navigationTitle(L10n.tr("Kanallar")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            VStack(spacing: 2) {
                                Text(L10n.tr("Kanallar")).font(.headline)
                                if let source = model.playbackSource {
                                    Text(source.name).font(.caption).foregroundStyle(MirrorStyle.secondary).lineLimit(1)
                                }
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("Kapat"), systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly).accessibilityIdentifier("close-playback-queue")
                        }
                    }
            } else {
                ChannelBrowserView(channels: model.playbackQueue,
                               title: currentSeries?.title ?? model.selectedMediaChannel.flatMap { $0.group.isEmpty ? nil : $0.group } ?? model.playbackSource?.name ?? L10n.tr("Oynatma listesi"),
                               sourceID: model.playbackSourceID,
                               showsCategories: model.selectedMediaChannel?.isAudio == true,
                               playlistChannels: model.playbackQueue,
                               onSelectChannel: selectChannel,
                               series: currentSeries, initialSeason: model.selectedMediaChannel?.episode?.season,
                               showsSearch: currentSeries == nil,
                               sortScope: "playback:" + (model.selectedMediaChannel?.group ?? ""))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("Kapat"), systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly).accessibilityIdentifier("close-playback-queue")
                        }
                    }
            }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark)
            .presentationDetents([.fraction(0.75), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .task { await model.restorePlaybackQueueFromSource() }
            .alert(BrandIdentity.name, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(L10n.tr("Tamam")) { message = nil }
            } message: { Text(message ?? "") }
    }
    private func selectChannel(_ channel: MediaChannel) {
        if model.playMedia(channel, queue: model.playbackQueue, sourceID: model.playbackSourceID) {
            dismiss()
        } else if let error = model.errorMessage {
            message = error
            model.errorMessage = nil
        }
    }
}
