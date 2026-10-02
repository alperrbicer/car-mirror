import Foundation

/// Only encoded media lives here. No screen frames or segments are written to disk.
public final class HLSBuffer: @unchecked Sendable {
    public struct Segment: Sendable {
        public let sequence: Int
        public let duration: Double
        public let data: Data
    }

    public struct Snapshot: Sendable {
        public let segments: [Segment]
        public let initialization: Data?
        public let totalSegments: Int
        public let byteCount: Int
        public var isReady: Bool { initialization != nil && segments.count >= 3 }
    }

    private let lock = NSLock()
    private var initialization: Data?
    private var segments: [Segment] = []
    private var sequence = 0
    private var bytes = 0
    private var accepting = true
    public let targetDuration = 2
    public let maximumBytes: Int
    private let retainedSegments: Int
    private let playlistSegments: Int

    public init(maximumBytes: Int = 8 * 1_024 * 1_024, retainedSegments: Int = 10, playlistSegments: Int = 6) {
        self.maximumBytes = maximumBytes
        self.retainedSegments = max(3, retainedSegments)
        self.playlistSegments = max(3, min(playlistSegments, retainedSegments))
    }

    @discardableResult
    public func setInitialization(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard accepting, data.count <= maximumBytes / 4 else { return false }
        bytes -= initialization?.count ?? 0
        initialization = data
        bytes += data.count
        trim()
        return true
    }

    @discardableResult
    public func append(_ data: Data, duration: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // The target duration of a live playlist must remain constant.
        guard accepting, duration.isFinite, duration > 0,
              duration.rounded() <= Double(targetDuration),
              data.count <= maximumBytes / 3 else { return false }
        segments.append(Segment(sequence: sequence, duration: duration, data: data))
        sequence += 1
        bytes += data.count
        trim()
        return true
    }

    private func trim() {
        while !segments.isEmpty && (segments.count > retainedSegments || bytes > maximumBytes) {
            bytes -= segments.removeFirst().data.count
        }
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(segments: segments, initialization: initialization, totalSegments: sequence, byteCount: bytes)
    }

    public func media(named name: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return nil }
        if name == "init.mp4" { return initialization }
        guard name.hasPrefix("segment-"), name.hasSuffix(".m4s"),
              let number = Int(name.dropFirst(8).dropLast(4)) else { return nil }
        return segments.first { $0.sequence == number }?.data
    }

    public func playlist() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard accepting, initialization != nil, segments.count >= 3 else { return nil }
        let visible = Array(segments.suffix(playlistSegments))
        let lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:\(targetDuration)",
                     "#EXT-X-MEDIA-SEQUENCE:\(visible[0].sequence)", "#EXT-X-INDEPENDENT-SEGMENTS",
                     "#EXT-X-MAP:URI=\"init.mp4\""]
        let entries = visible.flatMap { segment in
            [String(format: "#EXTINF:%.4f,", locale: Locale(identifier: "en_US_POSIX"), segment.duration),
             "segment-\(segment.sequence).m4s"]
        }
        return Data((lines + entries).joined(separator: "\n").appending("\n").utf8)
    }

    /// Permanently revoke this session; late encoder callbacks cannot restore old media.
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        accepting = false
        initialization = nil
        segments.removeAll(keepingCapacity: false)
        bytes = 0
    }
}
