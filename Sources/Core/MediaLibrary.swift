import Foundation

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
    public init(title: String, group: String = "", url: URL) {
        self.id = url.absoluteString
        self.title = String(title.prefix(200))
        self.group = String(group.prefix(100))
        self.url = url
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
