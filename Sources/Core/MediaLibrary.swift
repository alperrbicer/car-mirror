import Foundation

public enum PlaybackTimeDisplay {
    public static func timestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--" }
        let whole = Int(seconds)
        let clock = String(format: "%02d:%02d", (whole / 60) % 60, whole % 60)
        return whole >= 3600 ? "\(whole / 3600):\(clock)" : clock
    }
}

public enum MediaSourceKind: String, Codable, CaseIterable, Sendable { case playlist, stream, xtream }

public struct MediaSource: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: MediaSourceKind
    public init(id: UUID = UUID(), name: String, kind: MediaSourceKind) {
        self.id = id; self.name = String(name.prefix(80)); self.kind = kind
    }
}

/// Sensitive URLs and server credentials are stored separately, in the Keychain.
public struct SourceSecret: Codable, Sendable {
    public var url: URL
    public var username: String?
    public var password: String?
    public init(url: URL, username: String? = nil, password: String? = nil) {
        self.url = url; self.username = username; self.password = password
    }
}

public struct MediaChannel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let group: String
    public let url: URL
    public var requiresCompatibilityPlayback: Bool {
        ["mkv", "webm", "avi", "ts"].contains(url.pathExtension.lowercased())
    }
    public var isLive: Bool {
        !["mkv", "mp4", "m4v", "mov", "avi", "webm"].contains(url.pathExtension.lowercased())
    }
    public init(title: String, group: String = "", url: URL) {
        self.id = url.absoluteString
        self.title = String(title.prefix(200))
        self.group = String(group.prefix(100))
        self.url = url
    }
}

public struct MediaChannelCategory: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public var channels: [MediaChannel]

    /// Preserve provider order, including channels with no category metadata.
    public static func group(_ channels: [MediaChannel]) -> [MediaChannelCategory] {
        var result: [MediaChannelCategory] = []
        var indices: [String: Int] = [:]
        for channel in channels {
            let name = channel.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = indices[name] { result[index].channels.append(channel) }
            else {
                indices[name] = result.count
                result.append(MediaChannelCategory(name: name, channels: [channel]))
            }
        }
        return result
    }
}

public enum LibraryError: Error { case invalidURL, unsupportedURL, emptyPlaylist, tooLarge, invalidResponse, credentials, storage }

public enum MediaURL {
    public static func validate(_ input: String, relativeTo base: URL? = nil) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 8_192, !value.contains("\n"), !value.contains("\r"),
              let url = URL(string: value, relativeTo: base)?.absoluteURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host, !host.isEmpty else { throw LibraryError.invalidURL }
        // Never allow a playlist to launch file:, javascript:, or an application URL.
        guard ["http", "https"].contains(components.scheme?.lowercased() ?? "") else { throw LibraryError.unsupportedURL }
        guard components.user == nil, components.password == nil else { throw LibraryError.credentials }
        return url
    }
}

public enum M3UParser {
    public static let maximumBytes = 5 * 1_024 * 1_024
    public static let maximumChannels = 20_000
    public static func parse(_ data: Data, baseURL: URL, fallbackTitle: String) throws -> [MediaChannel] {
        guard data.count <= maximumBytes else { throw LibraryError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw LibraryError.invalidResponse }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).hasPrefix("#EXTM3U") else {
            throw LibraryError.invalidResponse
        }
        // An HLS manifest is one playable channel, not a list of transport segments.
        if text.contains("#EXT-X-TARGETDURATION:") || text.contains("#EXT-X-STREAM-INF:") {
            return [MediaChannel(title: fallbackTitle, url: baseURL)]
        }
        var title: String?, group = "", channels: [MediaChannel] = [], seen: Set<String> = []
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                // Commas inside quoted attributes do not terminate metadata.
                var quoted = false
                let comma = line.indices.first { index in
                    if line[index] == "\"" { quoted.toggle() }
                    return line[index] == "," && !quoted
                }
                title = comma.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) }
                group = attribute("group-title", in: line) ?? ""
            } else if line.hasPrefix("#EXTGRP:") { group = String(line.dropFirst(8)) }
            else if !line.isEmpty, !line.hasPrefix("#") {
                defer { title = nil; group = "" }
                guard let url = try? MediaURL.validate(line, relativeTo: baseURL), seen.insert(url.absoluteString).inserted else { continue }
                channels.append(MediaChannel(title: title?.isEmpty == false ? title! : fallbackTitle, group: group, url: url))
                if channels.count >= maximumChannels { break }
            }
        }
        guard !channels.isEmpty else { throw LibraryError.emptyPlaylist }
        return channels
    }
    private static func attribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: name + "=\"") else { return nil }
        return line[range.upperBound...].split(separator: "\"", omittingEmptySubsequences: false).first.map(String.init)
    }
}

public enum XtreamEndpoint {
    /// The same Xtream account can be added as a playlist URL or as server credentials.
    /// Ask for HLS and category metadata in both cases; never rename channel URLs.
    public static func nativePlaylistURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.hasSuffix("/get.php"),
              let items = components.queryItems,
              items.contains(where: { $0.name == "username" && !($0.value ?? "").isEmpty }),
              items.contains(where: { $0.name == "password" && !($0.value ?? "").isEmpty }),
              items.contains(where: { $0.name == "type" && ["m3u", "m3u_plus", "std_m3u"].contains($0.value ?? "") }) else { return url }
        let types = items.filter { $0.name == "type" }
        let outputs = items.filter { $0.name == "output" }
        guard types.count == 1, outputs.count <= 1,
              outputs.isEmpty || ["ts", "mpegts", "m3u8"].contains(outputs[0].value?.lowercased() ?? "") else { return url }
        // Keep exact encoded credentials, field order and unrelated query fields intact.
        var fields = (components.percentEncodedQuery ?? "").components(separatedBy: "&")
        fields = fields.map { field in
            switch field.components(separatedBy: "=").first?.removingPercentEncoding {
            case "type": return "type=m3u_plus"
            case "output": return "output=m3u8"
            default: return field
            }
        }
        if outputs.isEmpty { fields.append("output=m3u8") }
        components.percentEncodedQuery = fields.joined(separator: "&")
        return components.url ?? url
    }

    public static func playlist(secret: SourceSecret) throws -> URL {
        guard let user = secret.username, !user.isEmpty, let password = secret.password, !password.isEmpty,
              var components = URLComponents(url: secret.url, resolvingAgainstBaseURL: true) else { throw LibraryError.credentials }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "/get.php" : components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).appending("/get.php")
        if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        components.queryItems = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus"), URLQueryItem(name: "output", value: "m3u8")]
        components.fragment = nil
        guard let url = components.url else { throw LibraryError.invalidURL }
        return url
    }
}
