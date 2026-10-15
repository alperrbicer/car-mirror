import SwiftUI
import ImageIO

/// Provider artwork is decoded at thumbnail size and kept only in bounded memory.
@MainActor
private final class MediaArtworkStore {
    static let shared = MediaArtworkStore()
    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    init() {
        cache.totalCostLimit = 24 * 1_024 * 1_024
        cache.countLimit = 160
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func image(at url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = await Self.fetch(url, session: session), !Task.isCancelled else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }

    // Reading and decoding large images must never occupy the UI actor.
    nonisolated private static func fetch(_ url: URL, session: URLSession) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.setValue("Mirivo/1.0", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            let limit = 4 * 1_024 * 1_024
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  response.expectedContentLength <= limit else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { return nil }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        } catch { return nil }
    }
}

struct MediaArtworkView: View {
    let channel: MediaChannel
    var artworkURL: URL?
    var cornerRadius: CGFloat = 14
    @State private var image: UIImage?
    private var url: URL? { artworkURL ?? channel.metadata.artworkURL }
    private var isLogo: Bool { channel.isLive || channel.isAudio }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [tint.opacity(0.42), MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: isLogo ? .fit : .fill)
                        .padding(isLogo ? 10 : 0)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Circle().stroke(tint.opacity(0.22), lineWidth: 1)
                        .frame(width: geometry.size.width * 1.2).offset(x: geometry.size.width * 0.35, y: -geometry.size.height * 0.2)
                    VStack(spacing: 8) {
                        Image(systemName: channel.isAudio ? "waveform" : channel.isLive ? "tv" : "film")
                            .font(.system(size: min(28, geometry.size.width * 0.28), weight: .light))
                        if geometry.size.height > 85 {
                            Text(initials).font(.system(size: min(22, geometry.size.width * 0.18), weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                    }.foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.08)) }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            let result = await MediaArtworkStore.shared.image(at: url)
            guard !Task.isCancelled else { return }
            image = result
        }
    }

    private var initials: String {
        String(channel.title.split(whereSeparator: { $0.isWhitespace || $0 == ":" }).prefix(2).compactMap(\.first)).uppercased()
    }
    private var tint: Color {
        let palette: [Color] = [MirrorStyle.accent, .indigo, .orange, .cyan, .purple, .pink]
        let seed = channel.title.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xffff }
        return palette[seed % palette.count]
    }
}

struct ChannelCategoryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let count: Int
    let preview: [MediaChannel]
    var prominent = false

    init(name: String, channels: [MediaChannel], prominent: Bool = false) {
        self.name = name; count = channels.count; self.prominent = prominent
        var seen: Set<URL> = []
        var preview: [MediaChannel] = []
        for channel in channels {
            if let url = channel.metadata.artworkURL, seen.insert(url).inserted { preview.append(channel) }
            if preview.count == 3 { break }
        }
        self.preview = preview.isEmpty ? Array(channels.prefix(3)) : preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                let count = CGFloat(max(preview.count, 1))
                let coverWidth = min(prominent ? 76.0 : 62.0, max(28, (geometry.size.width - 12 + (count - 1) * 12) / count))
                ZStack {
                    Ellipse().fill(MirrorStyle.accent.opacity(prominent ? 0.12 : 0.06)).blur(radius: 18)
                    HStack(spacing: -12) {
                        ForEach(Array(preview.enumerated()), id: \.element.id) { index, channel in
                            MediaArtworkView(channel: channel, cornerRadius: 12)
                                .frame(width: coverWidth, height: channel.isLive ? 68 : 94)
                                .rotationEffect(.degrees(Double(index - (preview.count - 1) / 2) * 8))
                                .offset(y: index == 1 ? -5 : 4)
                                .shadow(color: .black.opacity(0.3), radius: 7, y: 5)
                                .zIndex(index == 1 ? 1 : 0)
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(height: 106).padding(.top, 4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(name).font(prominent ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .frame(minHeight: prominent || dynamicTypeSize.isAccessibilitySize ? nil : 40, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(String(format: L10n.tr("%d içerik"), count))
                        .font(.caption).foregroundStyle(MirrorStyle.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.accent)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [prominent ? MirrorStyle.raised : MirrorStyle.surface, MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(prominent ? MirrorStyle.accent.opacity(0.22) : MirrorStyle.hairline) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
