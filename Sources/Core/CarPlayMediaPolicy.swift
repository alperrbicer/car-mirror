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

/// A finite timeline whose independently encoded segments can be requested in
/// any order. No future media is declared available in a rolling live window.
public struct CarPlayVODPlaylist: Sendable {
    public let duration: Double
    public let startPosition: Double
    public let segmentDuration: Double = 16
    public var segmentCount: Int { Int(ceil(duration / segmentDuration)) }

    public init(duration: Double, startPosition: Double = 0) throws {
        guard duration.isFinite, duration > 0, duration <= 86_400,
              startPosition.isFinite else { throw URLError(.cannotDecodeContentData) }
        self.duration = duration
        self.startPosition = min(max(0, startPosition), max(0, duration - 0.001))
    }

    public func interval(for index: Int) -> Range<Double>? {
        guard (0..<segmentCount).contains(index) else { return nil }
        let start = Double(index) * segmentDuration
        return start..<min(start + segmentDuration, duration)
    }

    public func name(for index: Int) -> String { "vod-\(index).ts" }

    public func index(for name: String) -> Int? {
        guard name.hasPrefix("vod-"), name.hasSuffix(".ts"),
              let index = Int(name.dropFirst(4).dropLast(3)), interval(for: index) != nil,
              self.name(for: index) == name else { return nil }
        return index
    }

    /// VLC may write a few frames from time zero before applying start-time.
    /// Keep complete PES units from the requested range and repair TS counters.
    public static func removingSeekPreroll(from data: Data, before seconds: Double) throws -> Data {
        guard seconds.isFinite, seconds >= 0, !data.isEmpty, data.count % 188 == 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        guard seconds > 0 else { return data }
        let bytes = [UInt8](data)
        var accepted: [Int: Bool] = [:]
        var counters: [Int: UInt8] = [:]
        var firstTimestamp: UInt64?
        var result = Data(capacity: data.count)
        for start in stride(from: 0, to: bytes.count, by: 188) {
            var packet = Array(bytes[start..<(start + 188)])
            guard packet[0] == 0x47 else { throw URLError(.cannotDecodeContentData) }
            let pid = Int(packet[1] & 0x1f) << 8 | Int(packet[2])
            let control = (packet[3] >> 4) & 3
            guard control != 0 else { throw URLError(.cannotDecodeContentData) }
            let payload = 4 + (control & 2 == 0 ? 0 : 1 + Int(packet[4]))
            guard payload <= 188 else { throw URLError(.cannotDecodeContentData) }
            if control & 1 != 0, packet[1] & 0x40 != 0, payload + 14 <= 188,
               packet[payload] == 0, packet[payload + 1] == 0, packet[payload + 2] == 1,
               packet[payload + 7] & 0x80 != 0 {
                let p = payload + 9
                let ticks = UInt64((packet[p] >> 1) & 7) << 30 | UInt64(packet[p + 1]) << 22 |
                    UInt64(packet[p + 2] >> 1) << 15 | UInt64(packet[p + 3]) << 7 | UInt64(packet[p + 4] >> 1)
                accepted[pid] = Double(ticks) / 90_000 >= seconds
                if accepted[pid] == true, firstTimestamp == nil { firstTimestamp = ticks }
            }
            guard accepted[pid] != false else { continue }
            let counter = counters[pid].map { control & 1 != 0 ? ($0 + 1) & 0x0f : $0 } ?? (packet[3] & 0x0f)
            packet[3] = packet[3] & 0xf0 | counter
            counters[pid] = counter
            result.append(contentsOf: packet)
        }
        guard !result.isEmpty else { throw URLError(.cannotDecodeContentData) }
        // Each discontinuity starts an independent transport clock. Keep the
        // same 400-ms mux lead-in as the first segment, including PCR and DTS.
        if let firstTimestamp, firstTimestamp > 36_000 {
            let shift = firstTimestamp - 36_000, mask: UInt64 = (1 << 33) - 1
            var normalized = [UInt8](result)
            func adjusted(_ value: UInt64) -> UInt64 { (value + (1 << 33) - shift) & mask }
            func adjustPTS(at index: Int) {
                let value = UInt64((normalized[index] >> 1) & 7) << 30 | UInt64(normalized[index + 1]) << 22 |
                    UInt64(normalized[index + 2] >> 1) << 15 | UInt64(normalized[index + 3]) << 7 | UInt64(normalized[index + 4] >> 1)
                let next = adjusted(value)
                normalized[index] = normalized[index] & 0xf1 | UInt8((next >> 29) & 0x0e)
                normalized[index + 1] = UInt8((next >> 22) & 0xff)
                normalized[index + 2] = UInt8((next >> 14) & 0xfe) | 1
                normalized[index + 3] = UInt8((next >> 7) & 0xff)
                normalized[index + 4] = UInt8((next << 1) & 0xfe) | 1
            }
            for start in stride(from: 0, to: normalized.count, by: 188) {
                let control = (normalized[start + 3] >> 4) & 3
                let adaptation = control & 2 == 0 ? 0 : 1 + Int(normalized[start + 4])
                if adaptation >= 8, normalized[start + 5] & 0x10 != 0 {
                    let p = start + 6
                    let base = UInt64(normalized[p]) << 25 | UInt64(normalized[p + 1]) << 17 |
                        UInt64(normalized[p + 2]) << 9 | UInt64(normalized[p + 3]) << 1 | UInt64(normalized[p + 4] >> 7)
                    let next = adjusted(base)
                    normalized[p] = UInt8((next >> 25) & 0xff); normalized[p + 1] = UInt8((next >> 17) & 0xff)
                    normalized[p + 2] = UInt8((next >> 9) & 0xff); normalized[p + 3] = UInt8((next >> 1) & 0xff)
                    normalized[p + 4] = normalized[p + 4] & 0x7f | UInt8((next & 1) << 7)
                }
                let payload = start + 4 + adaptation
                if control & 1 != 0, normalized[start + 1] & 0x40 != 0, payload + 14 <= start + 188,
                   normalized[payload] == 0, normalized[payload + 1] == 0, normalized[payload + 2] == 1,
                   normalized[payload + 7] & 0x80 != 0 {
                    adjustPTS(at: payload + 9)
                    if normalized[payload + 7] & 0xc0 == 0xc0, payload + 19 <= start + 188 { adjustPTS(at: payload + 14) }
                }
            }
            result = Data(normalized)
        }
        return result
    }

    public var manifest: Data {
        func decimal(_ number: Double) -> String {
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), number)
        }
        var lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:16",
                     "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-INDEPENDENT-SEGMENTS",
                     "#EXT-X-START:TIME-OFFSET=\(decimal(startPosition)),PRECISE=YES"]
        for index in 0..<segmentCount {
            if index > 0 { lines.append("#EXT-X-DISCONTINUITY") }
            let length = min(segmentDuration, duration - Double(index) * segmentDuration)
            lines += ["#EXTINF:\(decimal(length)),", name(for: index)]
        }
        lines.append("#EXT-X-ENDLIST")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
