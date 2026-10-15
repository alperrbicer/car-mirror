import Foundation

/// Explicit episode notation only: years, resolutions and bare numbers are not episodes.
public struct MediaEpisode: Equatable, Sendable {
    public let seriesTitle: String
    public let season: Int
    public let number: Int
    public let title: String?
    public var seriesKey: String {
        seriesTitle.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).lowercased()
    }

    private static let patterns: [NSRegularExpression] = [
        #"(?i)(?:\s+|[._\-\[]+)S(\d{1,3})[\s._-]*E(\d{1,4})(?!\d)(?=$|[\s._\-\]:])"#,
        #"(?i)(?:\s+|[._\-\[]+)(\d{1,3})x(\d{1,4})(?!\d)(?=$|[\s._\-\]:])"#,
        #"(?i)\s+(\d{1,3})\.?\s*Sezon\s*[-.:]?\s*(\d{1,4})\.?\s*B[oö]l[uü]m\b"#,
        #"(?i)\s+Sezon\s*(\d{1,3})\s*[-.:]?\s*B[oö]l[uü]m\s*(\d{1,4})(?!\d)\b"#
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func parse(_ title: String) -> Self? {
        let title = String(title.prefix(200))
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "._-[]:–—"))
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let range = Range(match.range, in: title),
                  let seasonRange = Range(match.range(at: 1), in: title),
                  let numberRange = Range(match.range(at: 2), in: title),
                  let season = Int(title[seasonRange]), let number = Int(title[numberRange]) else { continue }
            let name = String(title[..<range.lowerBound]).trimmingCharacters(in: separators)
            guard !name.isEmpty else { continue }
            let episodeTitle = String(title[range.upperBound...]).trimmingCharacters(in: separators)
            return Self(seriesTitle: name, season: season, number: number, title: episodeTitle.isEmpty ? nil : episodeTitle)
        }
        return nil
    }
}

public struct MediaSeriesSeason: Identifiable, Equatable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let channels: [MediaChannel]
}

public struct MediaSeries: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let group: String
    public let seasons: [MediaSeriesSeason]
    public let channels: [MediaChannel]
    public var artworkChannel: MediaChannel? { channels.first { $0.metadata.artworkURL != nil } ?? channels.first }
}

public struct MediaSeriesCatalog: Sendable {
    public let series: [MediaSeries]
    public let ungrouped: [MediaChannel]

    public init(_ channels: [MediaChannel]) {
        var order: [String] = []
        var grouped: [String: [MediaChannel]] = [:]
        var ungrouped: [MediaChannel] = []
        for channel in channels {
            guard !channel.isLive, !channel.isAudio, let episode = channel.episode else {
                ungrouped.append(channel); continue
            }
            // A category may contain a different provider/version of the same series.
            let key = channel.group + "\u{1f}" + episode.seriesKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(channel)
        }
        self.ungrouped = ungrouped
        series = order.compactMap { key in
            guard let entries = grouped[key], let first = entries.first, let episode = first.episode else { return nil }
            let sorted = entries.enumerated().sorted { lhs, rhs in
                let a = lhs.element.episode!, b = rhs.element.episode!
                if a.season != b.season { return a.season < b.season }
                if a.number != b.number { return a.number < b.number }
                return lhs.offset < rhs.offset
            }.map(\.element)
            let bySeason = Dictionary(grouping: sorted) { $0.episode!.season }
            return MediaSeries(id: key, title: episode.seriesTitle, group: first.group,
                               seasons: bySeason.keys.sorted().map { MediaSeriesSeason(number: $0, channels: bySeason[$0]!) },
                               channels: sorted)
        }
    }

    public static func playbackQueue(for channel: MediaChannel, in channels: [MediaChannel]) -> [MediaChannel] {
        guard !channel.isLive, !channel.isAudio, let episode = channel.episode else { return channels }
        let matching = channels.filter { $0.group == channel.group && $0.episode?.seriesKey == episode.seriesKey }
        return Self(matching).series.first?.channels ?? [channel]
    }
}
