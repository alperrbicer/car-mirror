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

struct SeriesDetailHero: View {
    let series: MediaSeries
    let channel: MediaChannel
    let sourceID: UUID?
    let metadata: MediaMetadata
    let playChannel: MediaChannel?
    let onPlay: (() -> Void)?
    let showDetails: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            posterStage
            VStack(spacing: 8) {
                if !series.group.isEmpty {
                    Text(series.group)
                        .font(.caption2.weight(.semibold))
                        .tracking(L10n.appLanguage.allowsLetterSpacing ? 2 : 0)
                        .foregroundStyle(MirrorStyle.accent)
                        .multilineTextAlignment(.center)
                }
                Text(series.title)
                    .font(.largeTitle.weight(.bold))
                    .tracking(L10n.appLanguage.allowsLetterSpacing ? -1 : 0)
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { facts }
                    VStack(spacing: 8) { facts }
                }
                .font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                .frame(minHeight: 22)
                actions.padding(.top, 4)
            }
            .padding(.horizontal, 24).padding(.top, 2).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var posterStage: some View {
        ZStack {
            GeometryReader { geometry in
                let blurRadius: CGFloat = 28
                // Keep the artwork's edges outside the visible blur, then crop
                // the result to the stage. The blur needs transparent edges.
                MediaArtworkView(channel: channel, fallbackArtworkURL: metadata.artworkURL, cornerRadius: 0)
                    .frame(width: geometry.size.width + blurRadius * 6,
                           height: geometry.size.height + blurRadius * 6)
                    .compositingGroup()
                    .blur(radius: blurRadius).saturation(1.25).opacity(0.65)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        LinearGradient(colors: [MirrorStyle.background.opacity(0.15), .clear, MirrorStyle.background],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .clipped()
            .allowsHitTesting(false)
            // The oversized blur must not enlarge the hero's accessibility
            // frame over the episode buttons below it.
            .accessibilityElement(children: .ignore).accessibilityHidden(true)
            MediaArtworkPreviewButton(channel: channel, fallbackArtworkURL: metadata.artworkURL, cornerRadius: 16)
                .frame(width: 108, height: 156)
                .shadow(color: .black.opacity(0.55), radius: 24, y: 16)
                .overlay(alignment: .bottomTrailing) {
                    if let rating = metadata.rating {
                        Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.18)) }
                            .offset(x: 18, y: -12)
                            .accessibilityLabel(rating.formatted(.number.precision(.fractionLength(1))) + "/10")
                            .accessibilityIdentifier("media-rating")
                    }
                }
        }
        .frame(height: 172)
        .overlay(alignment: .topTrailing) {
            MediaFavoriteButton(channel: channel, sourceID: sourceID, scope: .series,
                                identifier: "series-detail-favorite")
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(MirrorStyle.hairline) }
                .padding(.trailing, 24).padding(.top, 12)
        }
    }

    @ViewBuilder private var facts: some View {
        if let year = metadata.year { Text(year) }
        Text(SeriesText.counts(series))
        if let duration = metadata.duration {
            Text(String(format: L10n.tr("%d dk"), Int(ceil(duration / 60))))
        }
    }

    private var actions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if let onPlay {
                Button(action: onPlay) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill").font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Oynat")).font(.headline)
                            if let episode = playChannel?.episode {
                                Text(SeriesText.episode(episode)).font(.caption)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .foregroundStyle(MirrorStyle.background)
                    .background(MirrorStyle.accent, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain).accessibilityIdentifier("series-play")
            }
            Button(action: showDetails) {
                VStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.title3)
                    Text(L10n.tr("İçerik bilgileri")).font(.caption.weight(.medium))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .foregroundStyle(.white)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(MirrorStyle.hairline) }
            }
            .buttonStyle(.plain).accessibilityIdentifier("media-details-toggle")
        }
    }
}

struct SeriesEpisodeRow<Download: View>: View {
    let channel: MediaChannel
    let play: () -> Void
    @ViewBuilder let download: () -> Download
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
            Button(action: play) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [MirrorStyle.raised, MirrorStyle.surface],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        if let episode = channel.episode {
                            Text(episode.number.formatted(.number.precision(.integerLength(2))))
                                .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Image(systemName: "play.fill").foregroundStyle(MirrorStyle.accent)
                        }
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 64 : 52,
                           height: dynamicTypeSize.isAccessibilitySize ? 72 : 52)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(channel.episode.map { SeriesText.episode($0.number) } ?? channel.title)
                            .font(.headline).foregroundStyle(.white)
                        if let title = channel.episode?.title {
                            Text(title).font(.subheadline).foregroundStyle(MirrorStyle.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        }
                        if let duration = channel.metadata.duration {
                            Text(String(format: L10n.tr("%d dk"), Int(ceil(duration / 60))))
                                .font(.caption).foregroundStyle(MirrorStyle.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(channel.title)
            HStack(spacing: 0) {
                if channel.isDownloadableVideo {
                    download().frame(width: 44, height: 44)
                }
                Button(action: play) {
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9)).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Oynat") + ": " + channel.title)
                .accessibilityIdentifier("series-episode-play-" + channel.id)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 14 : 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MirrorStyle.hairline).frame(height: 0.5)
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 80 : 68)
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
