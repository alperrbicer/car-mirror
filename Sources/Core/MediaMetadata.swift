import Foundation

/// Only descriptive fields are retained, never a provider's full API response.
public struct MediaMetadata: Codable, Equatable, Sendable {
    public let artworkURL: URL?
    public let summary: String?
    public let genre: String?
    public let year: String?
    public let duration: Double?
    public let rating: Double?
    public let director: String?
    public let cast: String?
    public let addedAt: Date?
    public let episodeTitle: String?

    public init(artworkURL: URL? = nil, summary: String? = nil, genre: String? = nil,
                year: String? = nil, duration: Double? = nil, rating: Double? = nil,
                director: String? = nil, cast: String? = nil, addedAt: Date? = nil, episodeTitle: String? = nil) {
        self.artworkURL = artworkURL.flatMap { try? MediaURL.validate($0.absoluteString) }
        self.summary = Self.clean(summary, limit: 6_000)
        self.genre = Self.clean(genre, limit: 200)
        let year = year.map { String($0.prefix(4)) }
        self.year = year.flatMap { Int($0) }.flatMap { (1800...2200).contains($0) ? String($0) : nil }
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 && $0 <= 604_800 ? $0 : nil }
        self.rating = rating.flatMap { $0.isFinite && $0 > 0 && $0 <= 10 ? $0 : nil }
        self.director = Self.clean(director, limit: 300)
        self.cast = Self.clean(cast, limit: 1_000)
        self.addedAt = addedAt.flatMap { $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 ? $0 : nil }
        self.episodeTitle = Self.clean(episodeTitle, limit: 200)
    }

    public func merging(_ other: Self) -> Self {
        Self(artworkURL: other.artworkURL ?? artworkURL, summary: other.summary ?? summary,
             genre: other.genre ?? genre, year: other.year ?? year, duration: other.duration ?? duration,
             rating: other.rating ?? rating, director: other.director ?? director, cast: other.cast ?? cast,
             addedAt: other.addedAt ?? addedAt, episodeTitle: other.episodeTitle ?? episodeTitle)
    }

    public static func addedDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds > 0, seconds < 4_102_444_800 {
            return Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: value)
    }

    public static func artworkURL(_ value: String?, relativeTo base: URL) -> URL? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? MediaURL.validate(value.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)
    }

    private static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        var result = String(text.prefix(limit * 2))
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        result = String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        return result.isEmpty || ["null", "n/a", "none"].contains(result.lowercased()) ? nil : result
    }
}

public extension XtreamEndpoint {
    static func vodCatalog(kind: MediaSourceKind, secret: SourceSecret, channel: MediaChannel) throws -> URL? {
        guard let (components, _) = try metadataEndpoint(kind: kind, secret: secret, channel: channel, route: "movie") else { return nil }
        return metadataURL(components, action: "get_vod_streams")
    }

    static func vodInfo(kind: MediaSourceKind, secret: SourceSecret, channel: MediaChannel) throws -> URL? {
        guard let (components, id) = try metadataEndpoint(kind: kind, secret: secret, channel: channel, route: "movie") else { return nil }
        return metadataURL(components, action: "get_vod_info", id: ("vod_id", id))
    }

    static func seriesLookup(kind: MediaSourceKind, secret: SourceSecret, channel: MediaChannel) throws -> XtreamSeriesLookup? {
        var endpoint = try metadataEndpoint(kind: kind, secret: secret, channel: channel, route: "series")
        // Some providers export series episodes through /movie/. Their episode ID
        // still has to be verified against get_series_info before using its metadata.
        if endpoint == nil, channel.episode != nil {
            endpoint = try metadataEndpoint(kind: kind, secret: secret, channel: channel, route: "movie")
        }
        guard let (components, id) = endpoint,
              let catalog = metadataURL(components, action: "get_series") else { return nil }
        return XtreamSeriesLookup(catalogURL: catalog, episodeID: id)
    }

    private static func metadataEndpoint(kind: MediaSourceKind, secret: SourceSecret, channel: MediaChannel,
                                         route: String) throws -> (URLComponents, String)? {
        guard kind != .stream else { return nil }
        let parts = channel.url.pathComponents
        guard parts.count >= 5, parts[parts.count - 4].lowercased() == route else { return nil }
        let id = channel.url.deletingPathExtension().lastPathComponent
        guard validMetadataID(id) else { return nil }
        let username = parts[parts.count - 3], password = parts[parts.count - 2]
        let endpoint: URL
        if let savedEndpoint = try accountInfo(kind: kind, secret: secret) {
            endpoint = savedEndpoint
        } else {
            // Ordinary M3U URLs need not be get.php. An explicit Xtream stream route
            // identifies its own API and account; credentials go back to that origin only.
            var base = channel.url
            for _ in 0..<4 { base.deleteLastPathComponent() }
            guard let inferred = try accountInfo(kind: .xtream, secret: SourceSecret(url: base, username: username, password: password)) else { return nil }
            endpoint = inferred
        }
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        let credentials = components.queryItems ?? []
        // Streams may use a different CDN host. Always query the saved source's API,
        // and require this stream to belong to the same account before looking up its ID.
        guard username == credentials.first(where: { $0.name == "username" })?.value,
              password == credentials.first(where: { $0.name == "password" })?.value else { return nil }
        return (components, id)
    }

    fileprivate static func validMetadataID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 20 && id.allSatisfy { $0.isASCII && $0.isNumber }
    }

    fileprivate static func metadataURL(_ endpoint: URLComponents, action: String, id: (String, String)? = nil) -> URL? {
        var components = endpoint
        var fields = (components.percentEncodedQuery ?? "").components(separatedBy: "&").filter {
            let name = $0.components(separatedBy: "=").first?.removingPercentEncoding ?? ""
            return !["action", "vod_id", "series_id", "stream_id", "category_id"].contains(name)
        }
        fields.append("action=" + action)
        if let (name, value) = id { fields.append(name + "=" + value) }
        components.percentEncodedQuery = fields.joined(separator: "&")
        return components.url
    }
}

public struct XtreamSeriesLookup: Sendable {
    public let catalogURL: URL
    public let episodeID: String

    /// The stream URL contains an episode ID, never the series ID required by this endpoint.
    public func infoURL(seriesID: String) -> URL? {
        guard XtreamEndpoint.validMetadataID(seriesID),
              let components = URLComponents(url: catalogURL, resolvingAgainstBaseURL: false) else { return nil }
        return XtreamEndpoint.metadataURL(components, action: "get_series_info", id: ("series_id", seriesID))
    }
}

public enum VODMetadataParser {
    public static let maximumBytes = 256 * 1_024

    public static func parse(_ data: Data, baseURL: URL) throws -> MediaMetadata {
        guard data.count <= maximumBytes else { throw LibraryError.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["info"] as? [String: Any] else { throw LibraryError.invalidResponse }
        let movie = metadata(root["movie_data"] as? [String: Any] ?? [:], baseURL: baseURL)
        return movie.merging(metadata(info, baseURL: baseURL))
    }

    fileprivate static func text(_ info: [String: Any], _ keys: String...) -> String? {
        keys.compactMap { key -> String? in
            if let value = info[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = info[key] as? NSNumber { return value.stringValue }
            return nil
        }.first
    }

    fileprivate static func metadata(_ info: [String: Any], baseURL: URL) -> MediaMetadata {
        func text(_ keys: String...) -> String? {
            keys.compactMap { Self.text(info, $0) }.first
        }
        let clock = text("duration")?.split(separator: ":", omittingEmptySubsequences: false)
        let duration = text("duration_secs").flatMap(Double.init) ?? clock.flatMap { values in
            let numbers = values.compactMap { Double($0) }
            guard (2...3).contains(values.count), numbers.count == values.count,
                  numbers.allSatisfy({ $0.isFinite && $0 >= 0 }), numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            return numbers.reduce(0) { $0 * 60 + $1 }
        }
        return MediaMetadata(
            artworkURL: MediaMetadata.artworkURL(text("movie_image", "cover_big", "cover"), relativeTo: baseURL),
            summary: ["plot", "description", "overview"].compactMap { MediaMetadata(summary: text($0)).summary }.first,
            genre: text("genre"), year: text("releasedate", "releaseDate", "release_date", "year"),
            duration: duration, rating: text("rating").flatMap(Double.init),
            director: text("director"), cast: text("cast", "actors"))
    }
}

public struct SeriesMetadataCandidate: Equatable, Sendable {
    public let id: String
    public let title: String
    public let metadata: MediaMetadata
}

public struct SeriesMetadataInfo: Sendable {
    public let metadata: MediaMetadata
    /// Episode-only fields, keyed by provider stream ID. Series duration/artwork
    /// must not be mistaken for an individual episode's duration/still.
    public let episodes: [String: MediaMetadata]
}

public enum SeriesMetadataParser {
    public static let maximumCatalogBytes = 8 * 1_024 * 1_024
    public static let maximumInfoBytes = 2 * 1_024 * 1_024

    public static func catalog(_ data: Data, baseURL: URL) throws -> [SeriesMetadataCandidate] {
        guard data.count <= maximumCatalogBytes else { throw LibraryError.tooLarge }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw LibraryError.invalidResponse }
        var seen = Set<String>()
        return rows.prefix(20_000).compactMap { row in
            guard let id = VODMetadataParser.text(row, "series_id"), XtreamEndpoint.validMetadataID(id),
                  let title = VODMetadataParser.text(row, "name"), seen.insert(id).inserted else { return nil }
            return SeriesMetadataCandidate(id: id, title: String(title.prefix(200)),
                                           metadata: VODMetadataParser.metadata(row, baseURL: baseURL))
        }
    }

    public static func candidates(in catalog: [SeriesMetadataCandidate], for channel: MediaChannel) -> [SeriesMetadataCandidate] {
        let title = normalized(channel.episode?.seriesTitle ?? channel.title)
        guard !title.isEmpty else { return [] }
        return catalog.enumerated().compactMap { index, candidate -> (Int, Int, SeriesMetadataCandidate)? in
            let name = normalized(candidate.title)
            let exact = title == name
            let sameArtwork = channel.metadata.artworkURL != nil && channel.metadata.artworkURL == candidate.metadata.artworkURL
            // Provider suffixes can differ between M3U and API names. These are only candidates:
            // the selected episode's stream ID must also occur in the series response.
            let prefix = !name.isEmpty && (title.hasPrefix(name + " ") || name.hasPrefix(title + " "))
            let similar = !exact && !prefix && Self.similarTitle(title, name)
            guard exact || sameArtwork || prefix || similar else { return nil }
            return (exact ? 0 : prefix ? 1 : sameArtwork ? 2 : 3, index, candidate)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.prefix(8).map { $0.2 }
    }

    public static func parseInfo(_ data: Data, episodeID: String, baseURL: URL, includeEpisode: Bool = true) throws -> MediaMetadata? {
        let info = try parseEpisodes(data, baseURL: baseURL)
        guard let episode = info.episodes[episodeID] else { return nil }
        return includeEpisode ? info.metadata.merging(episode) : info.metadata
    }

    public static func parseEpisodes(_ data: Data, baseURL: URL) throws -> SeriesMetadataInfo {
        guard data.count <= maximumInfoBytes else { throw LibraryError.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["info"] as? [String: Any] else { throw LibraryError.invalidResponse }
        let seasons: [Any]
        if let groups = root["episodes"] as? [String: Any] { seasons = Array(groups.values) }
        else if let groups = root["episodes"] as? [Any] { seasons = groups }
        else { throw LibraryError.invalidResponse }
        var result: [String: MediaMetadata] = [:]
        for season in seasons {
            guard let episodes = season as? [[String: Any]] else { continue }
            for episode in episodes {
                guard let id = VODMetadataParser.text(episode, "id", "stream_id"),
                      XtreamEndpoint.validMetadataID(id), result[id] == nil else { continue }
                let episodeInfo = episode["info"] as? [String: Any] ?? [:]
                let title = [VODMetadataParser.text(episode, "title"), VODMetadataParser.text(episode, "name"),
                             VODMetadataParser.text(episodeInfo, "title"), VODMetadataParser.text(episodeInfo, "name")]
                    .compactMap { MediaMetadata(episodeTitle: $0).episodeTitle }.first
                let details = VODMetadataParser.metadata(episode, baseURL: baseURL)
                    .merging(VODMetadataParser.metadata(episodeInfo, baseURL: baseURL))
                result[id] = details.merging(MediaMetadata(episodeTitle: title))
            }
        }
        return SeriesMetadataInfo(metadata: VODMetadataParser.metadata(info, baseURL: baseURL), episodes: result)
    }

    // Tolerate small provider spelling differences (for example Cafe / Kafe).
    // This only expands discovery: parseInfo still requires exact episode-ID membership.
    private static func similarTitle(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard min(a.count, b.count) >= 8 else { return false }
        let limit = min(2, min(a.count, b.count) / 8)
        guard abs(a.count - b.count) <= limit else { return false }
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var current = [i + 1]
            for (j, other) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1,
                                   previous[j] + (character == other ? 0 : 1)))
            }
            guard current.min()! <= limit else { return false }
            previous = current
        }
        return previous[b.count] <= limit
    }

    private static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
