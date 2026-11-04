import Foundation

/// CarPlay owns its video receiver. A TV/HDMI window is a different output.
public struct VideoOutputPolicy: Equatable, Sendable {
    public let systemCarPlay: Bool
    public let ownedDisplay: Bool
    public let allowsExternalPlayback: Bool

    public init(video: Bool, phone: Bool, carPlay: Bool, supportsVideo: Bool,
                externalDisplay: Bool, externalTV: Bool, cast: Bool) {
        systemCarPlay = video && !phone && carPlay && supportsVideo && !externalTV && !cast
        ownedDisplay = externalDisplay && !systemCarPlay
        allowsExternalPlayback = video && !phone && !cast && !ownedDisplay
    }
}

public enum CarPlayMediaSource {
    /// A candidate is only a probe; callers MUST validate an actual HLS response.
    /// Arbitrary playlist URLs, signed URLs and unrelated file paths are never renamed.
    public static func hlsCandidate(for url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              ["ts", "mkv", "avi", "webm"].contains(url.pathExtension.lowercased()) else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 5, ["live", "movie", "series"].contains(parts[parts.count - 4]),
              !parts[parts.count - 3].isEmpty, !parts[parts.count - 2].isEmpty,
              !url.deletingPathExtension().lastPathComponent.isEmpty,
              url.deletingPathExtension().lastPathComponent.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return url.deletingPathExtension().appendingPathExtension("m3u8")
    }

    public static func isHLS(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        return clean.hasPrefix("#EXTM3U") &&
            (clean.contains("#EXT-X-TARGETDURATION:") || clean.contains("#EXT-X-STREAM-INF:"))
    }
}

public enum HLSRelayPlaylist {
    /// Rewrite only URLs supplied by the selected manifest. Keep byte ranges,
    /// encryption metadata and non-HTTP DRM key schemes intact.
    public static func rewrite(_ data: Data, relativeTo base: URL,
                               map: (URL) throws -> URL) throws -> Data {
        guard CarPlayMediaSource.isHLS(data), let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let expression = try NSRegularExpression(pattern: #"\bURI="([^"]*)""#)
        func replacement(_ value: String) throws -> String {
            guard let url = URL(string: value, relativeTo: base)?.absoluteURL else { throw URLError(.badURL) }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return value }
            return try map(url).absoluteString
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        let lines = try normalized.components(separatedBy: .newlines).map { line -> String in
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { return line }
            if !clean.hasPrefix("#") { return try replacement(clean) }
            var result = line
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: result) else { continue }
                result.replaceSubrange(range, with: try replacement(String(result[range])))
            }
            return result
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
