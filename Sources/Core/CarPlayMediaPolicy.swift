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
    // The next range must be producible while the current one plays. A short
    // startup range followed by a much longer encode exhausts the first buffer.
    public let segmentDuration: Double = 6
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

    public func index(at time: Double) -> Int {
        guard time.isFinite else { return 0 }
        return min(segmentCount - 1, Int(max(0, min(time, duration)) / segmentDuration))
    }

    public func name(for index: Int) -> String { "vod-\(index).ts" }

    public func index(for name: String) -> Int? {
        guard name.hasPrefix("vod-"), name.hasSuffix(".ts"),
              let index = Int(name.dropFirst(4).dropLast(3)), interval(for: index) != nil,
              self.name(for: index) == name else { return nil }
        return index
    }

    /// A VLC seek can keep the source clock (with a few samples from before the
    /// seek), or start the entire output on a new clock. Both are valid HLS inputs.
    public static func removingSeekPreroll(from data: Data, before seconds: Double,
                                           duration: Double? = nil) throws -> Data {
        guard seconds.isFinite, seconds >= 0, duration.map({ $0.isFinite && $0 > 0 }) ?? true,
              !data.isEmpty, data.count % 188 == 0 else { throw URLError(.cannotDecodeContentData) }
        guard seconds > 0 || duration != nil else { return data }
        var bytes = [UInt8](data)
        var samples: [(packet: Int, ptsOffset: Int, ticks: UInt64)] = []
        let seekTicks = seconds * 90_000
        var previousVideoTime: Double?
        var usesSourceClock = false
        for start in stride(from: 0, to: bytes.count, by: 188) {
            let control = (bytes[start + 3] >> 4) & 3
            let adaptation = control & 2 == 0 ? 0 : 1 + Int(bytes[start + 4])
            let payload = start + 4 + adaptation
            guard bytes[start] == 0x47, control != 0, payload <= start + 188 else {
                throw URLError(.cannotDecodeContentData)
            }
            guard control & 1 != 0, bytes[start + 1] & 0x40 != 0, payload + 14 <= start + 188,
                  bytes[payload] == 0, bytes[payload + 1] == 0, bytes[payload + 2] == 1,
                  bytes[payload + 7] & 0x80 != 0 else { continue }
            let ticks = timestamp(in: bytes, at: payload + 9)
            samples.append((start, payload + 9, ticks))
            if (0xe0...0xef).contains(bytes[payload + 3]) {
                let time = Double(ticks)
                // On a source clock the first video sample is at the seek, or
                // the mux jumps there after its initial preroll. A continuous
                // segment-local clock can cross the same number during playback.
                if let previous = previousVideoTime {
                    if previous < seekTicks, time >= seekTicks, time - previous > 90_000 {
                        usesSourceClock = true
                    }
                } else if time >= seekTicks { usesSourceClock = true }
                previousVideoTime = time
            }
        }
        let lower = usesSourceClock ? seekTicks : 0
        guard previousVideoTime != nil,
              let origin = samples.lazy.map(\.ticks).filter({ Double($0) >= lower }).min() else {
            throw URLError(.cannotDecodeContentData)
        }
        let upper = duration.map { Double(origin) + $0 * 90_000 } ?? .infinity
        let shift = origin > 36_000 ? origin - 36_000 : 0
        if shift == 0, samples.allSatisfy({ (lower..<upper).contains(Double($0.ticks)) }) { return data }

        var accepted: [Int: Bool] = [:]
        var counters: [Int: UInt8] = [:]
        var sampleIndex = 0
        var result = Data(capacity: bytes.count)
        for start in stride(from: 0, to: bytes.count, by: 188) {
            let pid = Int(bytes[start + 1] & 0x1f) << 8 | Int(bytes[start + 2])
            let control = (bytes[start + 3] >> 4) & 3
            if sampleIndex < samples.count, samples[sampleIndex].packet == start {
                let sample = samples[sampleIndex]
                sampleIndex += 1
                accepted[pid] = (lower..<upper).contains(Double(sample.ticks))
                if shift != 0, accepted[pid] == true {
                    shiftTimestamp(in: &bytes, at: sample.ptsOffset, by: shift)
                    if bytes[sample.ptsOffset - 2] & 0xc0 == 0xc0, sample.ptsOffset + 10 <= start + 188 {
                        shiftTimestamp(in: &bytes, at: sample.ptsOffset + 5, by: shift)
                    }
                }
            }
            guard accepted[pid] != false else { continue }
            if shift != 0, control & 2 != 0, bytes[start + 4] >= 7, bytes[start + 5] & 0x10 != 0 {
                let p = start + 6
                let base = UInt64(bytes[p]) << 25 | UInt64(bytes[p + 1]) << 17 |
                    UInt64(bytes[p + 2]) << 9 | UInt64(bytes[p + 3]) << 1 | UInt64(bytes[p + 4] >> 7)
                let next = shifted(base, by: shift)
                bytes[p] = UInt8((next >> 25) & 0xff); bytes[p + 1] = UInt8((next >> 17) & 0xff)
                bytes[p + 2] = UInt8((next >> 9) & 0xff); bytes[p + 3] = UInt8((next >> 1) & 0xff)
                bytes[p + 4] = bytes[p + 4] & 0x7f | UInt8((next & 1) << 7)
            }
            let counter = counters[pid].map { control & 1 != 0 ? ($0 + 1) & 0x0f : $0 } ?? (bytes[start + 3] & 0x0f)
            bytes[start + 3] = bytes[start + 3] & 0xf0 | counter
            counters[pid] = counter
            result.append(contentsOf: bytes[start..<(start + 188)])
        }
        return result
    }

    private static func timestamp(in bytes: [UInt8], at p: Int) -> UInt64 {
        UInt64((bytes[p] >> 1) & 7) << 30 | UInt64(bytes[p + 1]) << 22 |
            UInt64(bytes[p + 2] >> 1) << 15 | UInt64(bytes[p + 3]) << 7 | UInt64(bytes[p + 4] >> 1)
    }

    private static func shifted(_ ticks: UInt64, by shift: UInt64) -> UInt64 {
        (ticks &- shift) & ((1 << 33) - 1)
    }

    private static func shiftTimestamp(in bytes: inout [UInt8], at p: Int, by shift: UInt64) {
        let next = shifted(timestamp(in: bytes, at: p), by: shift)
        bytes[p] = bytes[p] & 0xf1 | UInt8((next >> 29) & 0x0e)
        bytes[p + 1] = UInt8((next >> 22) & 0xff)
        bytes[p + 2] = UInt8((next >> 14) & 0xfe) | 1
        bytes[p + 3] = UInt8((next >> 7) & 0xff)
        bytes[p + 4] = UInt8((next << 1) & 0xfe) | 1
    }

    public var manifest: Data {
        func decimal(_ number: Double) -> String {
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), number)
        }
        var lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:\(Int(ceil(min(duration, segmentDuration))))",
                     "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-INDEPENDENT-SEGMENTS",
                     "#EXT-X-START:TIME-OFFSET=\(decimal(startPosition)),PRECISE=YES"]
        for index in 0..<segmentCount {
            if index > 0 { lines.append("#EXT-X-DISCONTINUITY") }
            let range = interval(for: index)!
            let length = range.upperBound - range.lowerBound
            lines += ["#EXTINF:\(decimal(length)),", name(for: index)]
        }
        lines.append("#EXT-X-ENDLIST")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
