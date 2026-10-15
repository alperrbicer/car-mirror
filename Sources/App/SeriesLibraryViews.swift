import SwiftUI

enum SeriesText {
    static func season(_ number: Int) -> String {
        number == 0 ? L10n.tr("Özel bölümler") : String(format: L10n.tr("%d. sezon"), number)
    }
    static func episode(_ number: Int) -> String { String(format: L10n.tr("%d. bölüm"), number) }
    static func episode(_ episode: MediaEpisode) -> String { season(episode.season) + " · " + self.episode(episode.number) }
    static func counts(_ series: MediaSeries) -> String {
        String(format: L10n.tr("%d sezon"), series.seasons.count) + " · " + String(format: L10n.tr("%d bölüm"), series.channels.count)
    }
}

struct SeriesPosterCard: View {
    let series: MediaSeries
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let channel = series.artworkChannel {
                MediaArtworkView(channel: channel, cornerRadius: 18)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "rectangle.stack.fill").font(.system(size: 14))
                            .foregroundStyle(.white).padding(10).background(.black.opacity(0.65), in: Circle()).padding(10)
                    }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(series.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 40, alignment: .topLeading)
                Text(SeriesText.counts(series)).font(.caption).foregroundStyle(MirrorStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 2)
        }.contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct SeriesLibraryHeader: View {
    let series: MediaSeries
    let sourceID: UUID?
    var body: some View {
        if let channel = series.artworkChannel {
            MediaDetailsView(channel: channel,
                             source: SourceLibrary.shared.sources.first { $0.id == sourceID }, series: series)
        }
    }
}

/// Older history entries may predate artwork storage. Resolve only their own source.
struct ContinueWatchingArtwork: View {
    let entry: LastPlaybackRecord
    var cornerRadius: CGFloat = 12
    @State private var resolved: MediaChannel?
    var body: some View {
        MediaArtworkView(channel: resolved ?? entry.channel, cornerRadius: cornerRadius)
            .task(id: entry.url) {
                resolved = nil
                guard entry.metadata?.artworkURL == nil, let id = entry.sourceID,
                      let source = SourceLibrary.shared.sources.first(where: { $0.id == id }) else { return }
                // SourceLibrary coalesces concurrent requests from all visible cards.
                guard let channels = try? await SourceLibrary.shared.channels(for: source), !Task.isCancelled else { return }
                resolved = channels.first { $0.url == entry.url }
            }
    }
}
