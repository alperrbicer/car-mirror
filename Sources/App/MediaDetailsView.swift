import SwiftUI

actor MediaMetadataLoader {
    typealias Response = (data: Data, url: URL)
    typealias Fetch = @Sendable (URL, Int) async throws -> Response
    static let shared = MediaMetadataLoader()
    private let fetch: Fetch
    private var catalogs: [URL: (date: Date, entries: [SeriesMetadataCandidate])] = [:]

    init(fetch: @escaping Fetch = MediaMetadataLoader.request) { self.fetch = fetch }

    static func load(source: MediaSource, channel: MediaChannel, seriesOnly: Bool = false) async throws -> MediaMetadata? {
        let secret = try SourceKeychain.read(source.id)
        return try await shared.load(kind: source.kind, secret: secret, channel: channel, seriesOnly: seriesOnly)
    }

    func load(kind: MediaSourceKind, secret: SourceSecret, channel: MediaChannel, seriesOnly: Bool = false) async throws -> MediaMetadata? {
        var seriesFailure: Error?
        if let lookup = try XtreamEndpoint.seriesLookup(kind: kind, secret: secret, channel: channel) {
            do {
                if let metadata = try await loadSeries(lookup, channel: channel, seriesOnly: seriesOnly) { return metadata }
            } catch {
                try Task.checkCancellation()
                seriesFailure = error
            }
        }
        if let url = try XtreamEndpoint.vodInfo(kind: kind, secret: secret, channel: channel) {
            let response = try await fetch(url, VODMetadataParser.maximumBytes)
            try Task.checkCancellation()
            let metadata = try VODMetadataParser.parse(response.data, baseURL: response.url)
            if metadata.summary == nil, let seriesFailure { throw seriesFailure }
            return metadata
        }
        if let seriesFailure { throw seriesFailure }
        return nil
    }

    private func loadSeries(_ lookup: XtreamSeriesLookup, channel: MediaChannel, seriesOnly: Bool) async throws -> MediaMetadata? {
        let catalog: [SeriesMetadataCandidate]
        if let cached = catalogs[lookup.catalogURL], Date().timeIntervalSince(cached.date) < 900 {
            catalog = cached.entries
        } else {
            let response = try await fetch(lookup.catalogURL, SeriesMetadataParser.maximumCatalogBytes)
            try Task.checkCancellation()
            catalog = try SeriesMetadataParser.catalog(response.data, baseURL: response.url)
            // Keep only descriptive fields, for at most three accounts, in memory.
            if catalogs.count >= 3, let oldest = catalogs.min(by: { $0.value.date < $1.value.date })?.key {
                catalogs.removeValue(forKey: oldest)
            }
            catalogs[lookup.catalogURL] = (Date(), catalog)
        }
        var failure: Error?
        for candidate in SeriesMetadataParser.candidates(in: catalog, for: channel) {
            try Task.checkCancellation()
            guard let url = lookup.infoURL(seriesID: candidate.id) else { continue }
            do {
                let response = try await fetch(url, SeriesMetadataParser.maximumInfoBytes)
                try Task.checkCancellation()
                if let metadata = try SeriesMetadataParser.parseInfo(response.data, episodeID: lookup.episodeID, baseURL: response.url, includeEpisode: !seriesOnly) {
                    return candidate.metadata.merging(metadata)
                }
            } catch {
                try Task.checkCancellation()
                failure = error
            }
        }
        if let failure { throw failure }
        return nil
    }

    nonisolated private static func request(_ url: URL, limit: Int) async throws -> Response {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Mirivo/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw LibraryError.invalidResponse }
        guard response.expectedContentLength <= limit else { throw LibraryError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw LibraryError.tooLarge }
            data.append(byte)
        }
        return (data, response.url ?? url)
    }
}

struct MediaDetailsView: View {
    let channel: MediaChannel
    let source: MediaSource?
    var series: MediaSeries?
    var playChannel: MediaChannel?
    var onPlay: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var loadedMetadata: MediaMetadata?
    @State private var showingDetails = false
    @State private var loading = true
    @State private var failed = false
    @State private var retry = 0
    private var metadata: MediaMetadata { channel.metadata.merging(loadedMetadata ?? MediaMetadata()) }
    private var contentID: String { "\(channel.id)|\(source?.id.uuidString ?? "")|\(series?.id ?? "")" }

    var body: some View {
        Group {
            if let series {
                SeriesDetailHero(series: series, channel: channel, metadata: metadata,
                                 playChannel: playChannel, onPlay: onPlay,
                                 showDetails: { showingDetails = true })
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Button { showingDetails = true } label: {
                        HStack(spacing: 10) {
                            Label(L10n.tr("İçerik bilgileri"), systemImage: "info.circle")
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(MirrorStyle.accent)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("media-details-toggle")
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 28))
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(MirrorStyle.hairline) }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("media-details")
        // Present details independently of the scroll layout. Animating a List
        // row's height while metadata arrives caused repeated offset corrections.
        // Read these states in the presenting body as well: a failed request
        // does not change metadata, so a lazy sheet must not retain "loading".
        .sheet(isPresented: $showingDetails) { [loading, failed] in
            informationSheet(loading: loading, failed: failed)
        }
        .onChange(of: contentID) { _, _ in showingDetails = false }
        .task(id: "\(contentID)|\(retry)") {
            loadedMetadata = nil; loading = true; failed = false
            defer { if !Task.isCancelled { loading = false } }
            guard let source else { return }
            do {
                let loaded = try await MediaMetadataLoader.load(source: source, channel: channel, seriesOnly: series != nil)
                guard !Task.isCancelled else { return }
                loadedMetadata = loaded
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }

    private func informationSheet(loading: Bool, failed: Bool) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    Rectangle().fill(MirrorStyle.hairline).frame(height: 1)
                    details(loading: loading, failed: failed)
                }
                .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MirrorStyle.background)
            .navigationTitle(L10n.tr("İçerik bilgileri"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Kapat"), systemImage: "xmark") { showingDetails = false }
                        .labelStyle(.iconOnly).tint(.white).accessibilityIdentifier("media-details-close")
                }
            }
        }
        .tint(MirrorStyle.accent).preferredColorScheme(.dark)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .accessibilityIdentifier("media-details-sheet")
    }

    private func details(loading: Bool, failed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let summary = metadata.summary {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("İçerik hakkında")).font(.subheadline.weight(.semibold))
                    Text(summary).font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("media-synopsis")
                }
            } else if loading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("İçerik bilgileri yükleniyor…")).font(.caption).foregroundStyle(MirrorStyle.secondary)
                }
            } else if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("İçerik bilgileri yüklenemedi."))
                        .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                        .accessibilityIdentifier("media-details-error")
                    Button(L10n.tr("Yeniden dene")) { retry += 1 }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent).frame(minHeight: 44)
                        .accessibilityIdentifier("media-details-retry")
                }
            } else {
                Text(L10n.tr("Bu içerik için açıklama bulunamadı."))
                    .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityIdentifier("media-details-empty")
            }
            if metadata.genre != nil || metadata.director != nil || metadata.cast != nil {
                VStack(alignment: .leading, spacing: 14) {
                    if let genre = metadata.genre { information("Tür", value: genre) }
                    if let director = metadata.director { information("Yönetmen", value: director) }
                    if let cast = metadata.cast { information("Oyuncular", value: cast) }
                }
                .padding(.top, 16).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(MirrorStyle.hairline).frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            MediaArtworkPreviewButton(channel: channel, fallbackArtworkURL: metadata.artworkURL)
                .frame(width: 76, height: channel.isLive || channel.isAudio ? 76 : 108)
            VStack(alignment: .leading, spacing: 9) {
                Text(series?.title ?? channel.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if !channel.group.isEmpty {
                    Text(channel.group).font(.caption).foregroundStyle(MirrorStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { facts }
                    VStack(alignment: .leading, spacing: 8) { facts }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var facts: some View {
        if let series {
            Text(SeriesText.counts(series)).font(.caption).foregroundStyle(MirrorStyle.accent)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label(L10n.tr(channel.isAudio ? "Ses" : channel.isLive ? "Canlı yayın" : "Video"),
                  systemImage: channel.isAudio ? "waveform" : channel.isLive ? "dot.radiowaves.left.and.right" : "film")
                .foregroundStyle(MirrorStyle.accent).font(.caption.weight(.medium))
        }
        if let year = metadata.year { Text(year).font(.caption).foregroundStyle(MirrorStyle.secondary) }
        if let duration = metadata.duration, !channel.isLive {
            Text(String(format: L10n.tr("%d dk"), Int(ceil(duration / 60))))
                .font(.caption).foregroundStyle(MirrorStyle.secondary)
        }
        if let rating = metadata.rating {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").accessibilityHidden(true)
                Text(rating.formatted(.number.precision(.fractionLength(1))) + "/10")
            }
            .font(.caption).foregroundStyle(.yellow).fixedSize()
            .accessibilityElement(children: .combine).accessibilityIdentifier("media-rating")
        }
    }

    private func information(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.tr(title)).font(.caption).foregroundStyle(MirrorStyle.secondary)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}
