import SwiftUI
import ImageIO
import CryptoKit

/// Compressed artwork survives relaunches; decoded thumbnails stay in bounded memory.
@MainActor
final class MediaArtworkStore {
    typealias Fetch = @MainActor (URL, URLSession, Int) async -> UIImage?
    static let shared = MediaArtworkStore()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let fetch: Fetch
    private final class Flight {
        let task: Task<UIImage?, Never>
        var readers: Set<UUID> = []
        init(task: Task<UIImage?, Never>) { self.task = task }
    }
    private var flights: [String: Flight] = [:]
    private var generation = 0

    init(fetch: @escaping Fetch = { url, session, size in
        await MediaArtworkStore.fetch(url, session: session, maximumPixelSize: size)
    }) {
        self.fetch = fetch
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

    func cachedImage(at url: URL, maximumPixelSize: Int = 600) -> UIImage? {
        cache.object(forKey: "\(maximumPixelSize)|\(url.absoluteString)" as NSString)
    }

    /// Restore only the first screen's saved artwork. Launch never waits for downloads.
    func prepareInitialArtwork(for channels: [MediaChannel]) async {
        let generation = generation
        let categories = MediaChannelCategory.group(channels)
        let preview = categories.contains(where: { !$0.name.isEmpty })
            ? categories.prefix(6).flatMap { MediaChannelCategory.artworkPreview($0.channels) }
            : Array(channels.prefix(8))
        let urls = Set(preview.compactMap { $0.metadata.artworkURL })
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { @MainActor in
                    guard self.cachedImage(at: url) == nil,
                          let image = await Self.diskImage(at: url, maximumPixelSize: 600),
                          !Task.isCancelled, self.generation == generation else { return }
                    self.cache.setObject(image, forKey: "600|\(url.absoluteString)" as NSString,
                                         cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
                }
            }
        }
    }

    func removeAll() {
        generation &+= 1
        cache.removeAllObjects()
        flights.values.forEach { $0.task.cancel() }
        flights.removeAll()
        Task { await MediaArtworkDiskCache.shared.removeAll() }
    }

    func image(at url: URL, maximumPixelSize: Int = 600) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(maximumPixelSize)|\(url.absoluteString)"
        if let image = cache.object(forKey: key as NSString) { return image }
        let flight: Flight
        if let pending = flights[key] { flight = pending }
        else {
            let fetch = fetch, session = session
            flight = Flight(task: Task { await fetch(url, session, maximumPixelSize) })
            flights[key] = flight
        }
        let reader = UUID()
        flight.readers.insert(reader)
        defer { release(reader, flight: flight, key: key) }
        let result = await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.release(reader, flight: flight, key: key) }
        }
        guard let image = result, !Task.isCancelled, !flight.task.isCancelled else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }

    private func release(_ reader: UUID, flight: Flight, key: String) {
        guard flight.readers.remove(reader) != nil, flight.readers.isEmpty else { return }
        flight.task.cancel()
        if flights[key] === flight { flights[key] = nil }
    }

    // Reading and decoding large images must never occupy the UI actor.
    nonisolated private static func fetch(_ url: URL, session: URLSession, maximumPixelSize: Int) async -> UIImage? {
        do {
            if let image = await diskImage(at: url, maximumPixelSize: maximumPixelSize) { return image }
            try Task.checkCancellation()
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
            guard let image = decode(data, maximumPixelSize: maximumPixelSize) else { return nil }
            await MediaArtworkDiskCache.shared.store(data, forKey: url.absoluteString)
            return image
        } catch { return nil }
    }

    nonisolated private static func diskImage(at url: URL, maximumPixelSize: Int) async -> UIImage? {
        guard let data = await MediaArtworkDiskCache.shared.data(forKey: url.absoluteString),
              !Task.isCancelled else { return nil }
        let image = decode(data, maximumPixelSize: maximumPixelSize)
        if image == nil { await MediaArtworkDiskCache.shared.remove(forKey: url.absoluteString) }
        return image
    }

    nonisolated private static func decode(_ data: Data, maximumPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

/// All disk work stays off the UI actor. Filenames never contain provider URLs or credentials.
actor MediaArtworkDiskCache {
    static let shared = MediaArtworkDiskCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("MirivoArtwork-v1", isDirectory: true))
    private let directory: URL?
    private let maximumBytes: Int
    private let maximumEntries: Int
    private let lifetime: TimeInterval
    private let maximumImageBytes = 4 * 1_024 * 1_024

    init(directory: URL?, maximumBytes: Int = 64 * 1_024 * 1_024, maximumEntries: Int = 512,
         lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumEntries = maximumEntries
        self.lifetime = lifetime
    }

    func data(forKey key: String, now: Date = Date()) -> Data? {
        guard !Task.isCancelled, let file = file(forKey: key) else { return nil }
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let date = values.contentModificationDate,
              now.timeIntervalSince(date) < lifetime,
              let size = values.fileSize, size > 0, size <= min(maximumBytes, maximumImageBytes),
              let data = try? Data(contentsOf: file), data.count == size else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return data
    }

    func store(_ data: Data, forKey key: String, now: Date = Date()) {
        guard !Task.isCancelled, !data.isEmpty, data.count <= min(maximumBytes, maximumImageBytes),
              maximumEntries > 0, let directory, let file = file(forKey: key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try excluded.setResourceValues(resources)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
            trim(now: now)
        } catch { /* A full or unavailable cache must not prevent displaying artwork. */ }
    }

    func remove(forKey key: String) {
        if let file = file(forKey: key) { try? FileManager.default.removeItem(at: file) }
    }

    func removeAll() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func file(forKey key: String) -> URL? {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name + ".artwork")
    }

    private func trim(now: Date) {
        guard let directory else { return }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        var entries: [(file: URL, date: Date, size: Int)] = []
        for file in files where file.pathExtension == "artwork" {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let date = values.contentModificationDate, now.timeIntervalSince(date) < lifetime,
                  let size = values.fileSize else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            entries.append((file, date, size))
        }
        var bytes = entries.reduce(0) { $0 + $1.size }, count = entries.count
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard bytes > maximumBytes || count > maximumEntries else { break }
            try? FileManager.default.removeItem(at: entry.file)
            bytes -= entry.size; count -= 1
        }
    }
}

struct MediaArtworkView: View {
    let channel: MediaChannel
    var fallbackArtworkURL: URL?
    var cornerRadius: CGFloat = 14
    @State private var image: UIImage?
    // Keep the catalog poster when details provide a different edition or cover.
    private var url: URL? { channel.metadata.artworkURL ?? fallbackArtworkURL }
    private var isLogo: Bool { channel.isLive || channel.isAudio }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [tint.opacity(0.42), MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = image ?? url.flatMap({ MediaArtworkStore.shared.cachedImage(at: $0) }) {
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
            image = url.flatMap { MediaArtworkStore.shared.cachedImage(at: $0) }
            guard let url, image == nil else { return }
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
        preview = MediaChannelCategory.artworkPreview(channels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(prominent ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.white).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(String(format: L10n.tr("%d içerik"), count))
                        .font(.caption).foregroundStyle(MirrorStyle.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
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

/// Detail posters open using the system zoom transition; catalog cards keep their navigation action.
struct MediaArtworkPreviewButton: View {
    let channel: MediaChannel
    var fallbackArtworkURL: URL?
    var cornerRadius: CGFloat = 14
    @Namespace private var transition
    @State private var showingPreview = false
    private var url: URL? { channel.metadata.artworkURL ?? fallbackArtworkURL }

    var body: some View {
        Button { showingPreview = true } label: {
            MediaArtworkView(channel: channel, fallbackArtworkURL: fallbackArtworkURL, cornerRadius: cornerRadius)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(channel.title)
        .accessibilityIdentifier("media-artwork-preview-open")
        .matchedTransitionSource(id: "poster", in: transition)
        .fullScreenCover(isPresented: $showingPreview) {
            MediaArtworkPreview(channel: channel, url: url)
                .navigationTransition(.zoom(sourceID: "poster", in: transition))
        }
    }
}

private struct MediaArtworkPreview: View {
    let channel: MediaChannel
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableArtwork(image: image, title: channel.title)
                    .ignoresSafeArea()
            } else {
                MediaArtworkView(channel: channel, fallbackArtworkURL: url, cornerRadius: 0)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: 400).padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain).padding(16)
            .accessibilityLabel(L10n.tr("Kapat"))
            .accessibilityIdentifier("media-artwork-preview-close")
        }
        .preferredColorScheme(.dark)
        .accessibilityAction(.escape) { dismiss() }
        .task(id: url) {
            guard let url else { return }
            image = await MediaArtworkStore.shared.image(at: url)
            guard !Task.isCancelled else { return }
            if let fullSize = await MediaArtworkStore.shared.image(at: url, maximumPixelSize: 2400), !Task.isCancelled {
                image = fullSize
            }
        }
    }
}

private struct ZoomableArtwork: UIViewRepresentable {
    let image: UIImage
    let title: String

    func makeUIView(context: Context) -> ArtworkZoomScrollView {
        let view = ArtworkZoomScrollView()
        view.imageView.accessibilityLabel = title
        return view
    }

    func updateUIView(_ view: ArtworkZoomScrollView, context: Context) {
        guard view.imageView.image !== image else { return }
        view.imageView.image = image
        view.setNeedsLayout()
    }
}

/// UIScrollView supplies native pinch, pan, bounce, and zoom gesture arbitration.
private final class ArtworkZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var fittedSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityIdentifier = "media-artwork-preview-image"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize, bounds.width > 0, bounds.height > 0, let image = imageView.image {
            fittedSize = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard zoomScale < 1.1 else { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
