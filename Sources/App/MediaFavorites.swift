import SwiftUI
import Security
import CryptoKit

struct FavoriteMedia: Codable, Identifiable, Equatable {
    struct SeriesReference: Codable, Equatable {
        let id: String
        let title: String
    }

    let record: LastPlaybackRecord
    // Optional so favorites saved before series support remain individual items.
    let series: SeriesReference?
    var channel: MediaChannel { record.channel }
    var sourceID: UUID? { record.sourceID }
    var title: String { series?.title ?? record.title }
    var id: String {
        series.map { Self.hash("series:" + $0.id, sourceID: sourceID) } ?? Self.id(channel, sourceID: sourceID)
    }

    init(channel: MediaChannel, sourceID: UUID?, wholeSeries: Bool = false) {
        record = LastPlaybackRecord(channel: channel, sourceID: sourceID, position: 0, duration: 0, isLive: channel.isLive)
        if wholeSeries, !channel.isLive, !channel.isAudio, let item = MediaSeriesCatalog([channel]).series.first {
            series = SeriesReference(id: item.id, title: item.title)
        } else { series = nil }
    }

    func resolveSeries(in channels: [MediaChannel]) -> MediaSeries? {
        guard let series else { return nil }
        return MediaSeriesCatalog(channels).series.first { $0.id == series.id }
    }

    func fallbackCatalog(currentChannels: [MediaChannel], sourceID currentSourceID: UUID?) -> [MediaChannel] {
        guard currentSourceID == sourceID else { return [channel] }
        return currentChannels.filter { $0.id != channel.id } + [channel]
    }

    static func id(_ channel: MediaChannel, sourceID: UUID?) -> String {
        hash(channel.id, sourceID: sourceID)
    }
    private static func hash(_ content: String, sourceID: UUID?) -> String {
        SHA256.hash(data: Data(((sourceID?.uuidString ?? "") + "|" + content).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct MediaFavoriteSelection {
    let item: FavoriteMedia
    let series: FavoriteMedia?
    let itemSelected: Bool
    let seriesSelected: Bool
}

@MainActor
final class MediaFavorites: ObservableObject {
    static let shared = MediaFavorites()
    @Published private(set) var entries: [FavoriteMedia] = []
    private var query: [String: Any]

    init(account: String = "favorites") {
        query = [kSecClass as String: kSecClassGenericPassword,
                 kSecAttrService as String: "com.alperbicer.carmirror.favorites",
                 kSecAttrAccount as String: account]
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            entries = (try? JSONDecoder().decode([FavoriteMedia].self, from: data)) ?? []
        }
    }

    func contains(_ channel: MediaChannel, sourceID: UUID?) -> Bool {
        contains(FavoriteMedia(channel: channel, sourceID: sourceID))
    }
    func contains(_ item: FavoriteMedia) -> Bool { entries.contains { $0.id == item.id } }

    func selection(for channel: MediaChannel, sourceID: UUID?) -> MediaFavoriteSelection {
        let item = FavoriteMedia(channel: channel, sourceID: sourceID)
        let candidate = FavoriteMedia(channel: channel, sourceID: sourceID, wholeSeries: true)
        let series = candidate.series == nil ? nil : candidate
        return MediaFavoriteSelection(item: item, series: series, itemSelected: contains(item),
                                      seriesSelected: series.map(contains) ?? false)
    }

    func toggle(_ channel: MediaChannel, sourceID: UUID?) throws {
        try toggle(FavoriteMedia(channel: channel, sourceID: sourceID))
    }

    func toggle(_ item: FavoriteMedia) throws {
        // Temporary personal files are deleted after playback and cannot be favorites.
        guard !item.channel.url.isFileURL else { return }
        var next = entries.filter { $0.id != item.id }
        if next.count == entries.count {
            next.insert(item, at: 0)
        }
        try persist(next)
    }

    func clear(sourceID: UUID? = nil) throws {
        try persist(sourceID.map { id in entries.filter { $0.sourceID != id } } ?? [])
    }

    private func persist(_ next: [FavoriteMedia]) throws {
        // URLs may contain provider credentials; keep them out of defaults/files.
        if next.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw LibraryError.storage }
        } else {
            let data = try JSONEncoder().encode(next)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LibraryError.storage }
            } else if status != errSecSuccess { throw LibraryError.storage }
        }
        entries = next
    }
}

struct MediaFavoriteButton: View {
    enum Scope { case item, series }
    let channel: MediaChannel
    let sourceID: UUID?
    var scope: Scope = .item
    var compact = false
    var playerChrome = false
    var identifier = "player-favorite"
    @ObservedObject private var favorites = MediaFavorites.shared
    @State private var failed = false
    private var selection: MediaFavoriteSelection { favorites.selection(for: channel, sourceID: sourceID) }
    private var selected: Bool {
        switch scope {
        // An episode's heart represents that episode, even when its series is saved.
        case .item: selection.itemSelected
        case .series: selection.series == nil ? selection.itemSelected : selection.seriesSelected
        }
    }
    private var accessibilityStatus: String {
        guard selected else { return L10n.tr("Favorilerde değil") }
        if scope == .series, selection.series != nil { return L10n.tr("Dizi favorilerde") }
        return channel.episode == nil ? L10n.tr("Favoriler") : L10n.tr("Bölüm favorilerde")
    }

    var body: some View {
        if !channel.url.isFileURL {
            Button { toggle(scope == .series ? selection.series ?? selection.item : selection.item) } label: { heart }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr(selected ? "Favorilerden çıkar" : "Favorilere ekle"))
            .accessibilityValue(accessibilityStatus)
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .alert(L10n.tr("Favoriler kaydedilemedi. Yeniden dene."), isPresented: $failed) {
                Button(L10n.tr("Tamam"), role: .cancel) {}
            }
        }
    }

    private var heart: some View {
        Image(systemName: selected ? "heart.fill" : "heart")
            .font(.system(size: compact ? 18 : 21, weight: playerChrome ? .medium : .semibold))
            .foregroundStyle(selected ? MirrorStyle.accent : .white)
            .frame(width: compact ? 36 : 48, height: compact ? 36 : 48)
            .background(.black.opacity(playerChrome ? 0 : 0.5), in: Circle())
            .frame(minWidth: playerChrome ? 40 : 44, minHeight: 44)
            .contentShape(Circle())
    }

    private func toggle(_ item: FavoriteMedia) {
        do { try favorites.toggle(item) }
        catch { failed = true }
    }
}

struct FavoritesBrowser: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var favorites = MediaFavorites.shared
    @State private var search = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var entries: [FavoriteMedia] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.entries.filter { term.isEmpty || $0.title.localizedStandardContains(term) }
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: 24) {
                ForEach(entries) { item in
                    card(item)
                }
            }
            .padding(16).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("favorites-grid")
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(L10n.tr(search.isEmpty ? "Favoriler" : "İçerik bulunamadı"),
                    systemImage: search.isEmpty ? "heart" : "magnifyingglass",
                    description: search.isEmpty ? Text(L10n.tr("Sevdiğin içerikleri kalp düğmesiyle buraya ekle.")) : nil)
            }
        }
        .searchable(text: $search, prompt: L10n.tr("Ara"))
        .navigationTitle(L10n.tr("Favoriler"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(MirrorStyle.background)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { NowPlayingBar { model.presentingPlayer = true } }
    }

    private func card(_ item: FavoriteMedia) -> some View {
        Group {
            if item.series != nil {
                NavigationLink { FavoriteSeriesBrowser(item: item) } label: { poster(item) }
            } else {
                Button {
                    let source = SourceLibrary.shared.sources.first { $0.id == item.sourceID }
                    let channels = source.flatMap { SourceLibrary.shared.cachedChannels(for: $0) } ?? [item.channel]
                    let queue = MediaSeriesCatalog.playbackQueue(for: item.channel, in: channels)
                    if model.playMedia(item.channel, queue: queue, sourceID: item.sourceID) { model.presentingPlayer = true }
                } label: { poster(item) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("favorite-open-" + item.title)
        .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .topLeading : .topTrailing) {
            MediaFavoriteButton(channel: item.channel, sourceID: item.sourceID, scope: item.series != nil ? .series : .item,
                                compact: true, identifier: "favorite-remove-" + item.id).padding(2)
        }
    }

    private func poster(_ item: FavoriteMedia) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return layout {
            ContinueWatchingArtwork(entry: item.record)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : nil,
                       height: dynamicTypeSize.isAccessibilitySize ? 144 : nil)
                .overlay(alignment: .bottomLeading) {
                    if item.series != nil || item.channel.episode != nil {
                        Text(L10n.tr(item.series != nil ? "Dizi" : "Bölüm")).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6)).padding(7)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let year = item.channel.metadata.year {
                    Text(year).font(.caption).foregroundStyle(MirrorStyle.secondary)
                }
            }
        }.contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

/// Resolve the current catalog instead of freezing the favorite's episode list.
private struct FavoriteSeriesBrowser: View {
    let item: FavoriteMedia
    @State private var series: MediaSeries?
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let series {
                ChannelBrowserView(channels: series.channels, title: series.title, sourceID: item.sourceID,
                                   showsCategories: false, playlistChannels: series.channels, series: series)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(L10n.tr(failed ? "İçerikler yüklenemedi." : "İçerik bulunamadı"), systemImage: "rectangle.stack")
                } actions: {
                    Button(L10n.tr("Yeniden dene")) { retry += 1 }
                }
            }
        }
        .background(MirrorStyle.background)
        .toolbar(.visible, for: .navigationBar)
        .task(id: retry) {
            loading = true; failed = false
            defer { loading = false }
            guard let source = SourceLibrary.shared.sources.first(where: { $0.id == item.sourceID }) else {
                if item.sourceID == nil {
                    let model = MirrorModel.shared
                    series = item.resolveSeries(in: item.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID))
                }
                return
            }
            do {
                let channels = try await SourceLibrary.shared.channels(for: source, reload: retry > 0)
                guard !Task.isCancelled else { return }
                series = item.resolveSeries(in: channels)
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
