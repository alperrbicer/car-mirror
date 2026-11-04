import Foundation
#if SWIFT_PACKAGE
import MirrorCore
#endif

public enum CarPlayMediaResolver {
    /// Never hand a guessed .m3u8 URL to AVPlayer. Some Xtream providers expose
    /// an HLS rendition; others serve only the original MKV/TS container.
    public static func nativeAlternative(for source: URL) async throws -> URL? {
        guard let candidate = CarPlayMediaSource.hlsCandidate(for: source) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        // This is only a fast path for live TS providers. A missing rendition
        // must not hold playback for eight seconds before local conversion.
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: candidate)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { return nil }
            data.append(byte)
            // Do not download a movie when a provider ignores the requested format.
            if data.count == 64, !String(decoding: data, as: UTF8.self).contains("#EXTM3U") { return nil }
            if byte == 10, CarPlayMediaSource.isHLS(data),
               String(decoding: data, as: UTF8.self).components(separatedBy: "\n").contains(where: {
                   let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                   return !line.isEmpty && !line.hasPrefix("#")
               }) { return candidate }
        }
        return CarPlayMediaSource.isHLS(data) ? candidate : nil
    }
}
