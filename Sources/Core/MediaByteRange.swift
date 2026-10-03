import Foundation

/// A single HTTP byte range, including suffix and open-ended requests used when seeking.
public struct MediaByteRange: Equatable, Sendable {
    public let start: Int64
    public let end: Int64
    public var length: Int64 { end - start + 1 }

    public static func parse(_ value: String, size: Int64) -> MediaByteRange? {
        guard size > 0, value.hasPrefix("bytes="), !value.contains(",") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        func number(_ text: Substring) -> Int64? {
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int64(text)
        }
        if parts[0].isEmpty {
            guard let suffix = number(parts[1]), suffix > 0 else { return nil }
            return MediaByteRange(start: max(0, size - suffix), end: size - 1)
        }
        guard let start = number(parts[0]), start < size else { return nil }
        let end: Int64
        if parts[1].isEmpty { end = size - 1 }
        else { guard let parsed = number(parts[1]), parsed >= start else { return nil }; end = min(parsed, size - 1) }
        return MediaByteRange(start: start, end: end)
    }
}
