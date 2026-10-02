import Foundation

/// Bounded stereo PCM timeline. Missing source audio is silence, never old audio.
/// Caller serializes access. Both media tracks use the same source-time origin.
public struct AudioTimeline {
    public static let sampleRate = 48_000
    public static let channels = 2
    private struct Chunk { var start: Int64; var samples: [Float]; var end: Int64 { start + Int64(samples.count / 2) } }
    private var chunks: [Chunk] = []
    public private(set) var consumed: Int64 = 0
    public private(set) var droppedFrames = 0
    private let maximumFrames = 96_000
    public init() {}
    public var bufferedFrames: Int { chunks.reduce(0) { $0 + $1.samples.count / 2 } }

    public mutating func append(samples: [Float], at start: Int64) {
        guard samples.count % 2 == 0, !samples.isEmpty else { return }
        let end = start + Int64(samples.count / 2)
        guard end > consumed, start < consumed + Int64(maximumFrames) else {
            droppedFrames += samples.count / 2; return
        }
        let trim = max(0, consumed - start)
        let available = min(samples.count / 2 - Int(trim), maximumFrames)
        chunks.append(Chunk(start: start + trim,
            samples: Array(samples[(Int(trim) * 2)..<((Int(trim) + available) * 2)])))
        chunks.sort { $0.start < $1.start }
        while bufferedFrames > maximumFrames, !chunks.isEmpty {
            droppedFrames += chunks.removeFirst().samples.count / 2
        }
    }

    public mutating func render(frameCount: Int) -> [Float] {
        let count = max(0, min(frameCount, maximumFrames))
        var result = [Float](repeating: 0, count: count * 2)
        let end = consumed + Int64(count)
        for chunk in chunks {
            let from = max(consumed, chunk.start), through = min(end, chunk.end)
            guard through > from else { continue }
            let source = Int(from - chunk.start) * 2, target = Int(from - consumed) * 2
            let length = Int(through - from) * 2
            result.replaceSubrange(target..<(target + length), with: chunk.samples[source..<(source + length)])
        }
        consumed = end
        chunks.removeAll { $0.end <= consumed }
        return result
    }
}
