import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MediaSharingView: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos: [PhotosPickerItem] = []
    @State private var video: PhotosPickerItem?
    @State private var pickingFiles = false
    @State private var openingLink = false
    @State private var slideshow: SlideshowSelection?
    @State private var showingPlayer = false
    @State private var pendingMedia: [MediaChannel] = []
    @State private var loading = false
    @State private var message: String?
    @State private var importTask: Task<Void, Never>?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MirivoSectionLabel(title: L10n.tr("Ne paylaşmak istersin?"))
            LazyVGrid(columns: columns, spacing: 12) {
                PhotosPicker(selection: $photos, maxSelectionCount: PhotoSlideshow.maximumPhotos,
                             selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current) {
                    tile("Fotoğraflar", detail: "Slayt gösterisi", symbol: "photo.stack", color: MirrorStyle.accent)
                }.accessibilityIdentifier("share-photos")
                PhotosPicker(selection: $video, matching: .videos, preferredItemEncoding: .current) {
                    tile("Videolar", detail: "Fotoğraf arşivinden", symbol: "play.rectangle", color: Color(red: 0.67, green: 0.74, blue: 1))
                }.accessibilityIdentifier("share-videos")
                Button { pickingFiles = true } label: {
                    tile("Müzik ve dosyalar", detail: "iPhone veya iCloud Drive", symbol: "music.note.list", color: Color(red: 1, green: 0.78, blue: 0.55))
                }.accessibilityIdentifier("share-files")
                Button { openingLink = true } label: {
                    tile("Bağlantı aç", detail: "Kaydetmeden oynat", symbol: "link", color: Color(red: 0.75, green: 0.67, blue: 1))
                }.accessibilityIdentifier("share-link")
            }
            .buttonStyle(.plain).disabled(loading)
            if loading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.tr("Medya hazırlanıyor…")).font(.subheadline)
                    Spacer(minLength: 0)
                    Button { importTask?.cancel(); importTask = nil; loading = false; photos = []; video = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel(L10n.tr("Kapat"))
                }.foregroundStyle(MirrorStyle.secondary)
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.movie, .audio] + ["mkv", "webm", "avi", "flac", "ogg", "opus"].compactMap { UTType(filenameExtension: $0) },
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure: message = L10n.tr("Medya açılamadı. Dosyanın indirildiğini ve boş alanı kontrol et.")
            }
        }
        .onChange(of: photos) { _, items in if !items.isEmpty { importPhotos(items) } }
        .onChange(of: video) { _, item in if let item { importVideo(item) } }
        .sheet(item: $slideshow, onDismiss: playPendingMedia) { selection in
            SlideshowEditor(selection: selection) { url in
                pendingMedia = [MediaChannel(title: L10n.tr("Slayt gösterisi"), url: url)]
            }
        }
        .sheet(isPresented: $openingLink, onDismiss: playPendingMedia) {
            QuickMediaLinkView { pendingMedia = [$0] }
        }
        .navigationDestination(isPresented: $showingPlayer) { MediaPlayerScreen(model: model) }
        .onDisappear { importTask?.cancel(); importTask = nil; loading = false }
    }

    private func tile(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(MirrorStyle.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr(title)).font(.headline).foregroundStyle(.white)
                Text(L10n.tr(detail)).font(.caption).foregroundStyle(MirrorStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(LinearGradient(colors: [color.opacity(0.045), MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(0.13)) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        beginImport()
        importTask = Task { @MainActor in
            var copied: [URL] = []
            do {
                for item in items {
                    guard let file = try await item.loadTransferable(type: PickedMediaFile.self) else { throw PersonalMediaError.unreadable }
                    copied.append(file.url)
                    try Task.checkCancellation()
                }
                slideshow = SlideshowSelection(urls: copied)
                loading = false
                photos = []
            } catch {
                PersonalMediaFiles.remove(copied)
                finishImportError(error)
            }
        }
    }

    private func importVideo(_ item: PhotosPickerItem) {
        beginImport()
        importTask = Task { @MainActor in
            var copied: [URL] = []
            do {
                guard let file = try await item.loadTransferable(type: PickedMediaFile.self) else { throw PersonalMediaError.unreadable }
                copied = [file.url]
                try Task.checkCancellation()
                loading = false
                video = nil
                play(copied.map { MediaChannel(title: $0.deletingPathExtension().lastPathComponent, url: $0) })
            } catch {
                PersonalMediaFiles.remove(copied)
                finishImportError(error)
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard urls.count <= 20 else { message = L10n.tr("En fazla 20 dosya seçebilirsin."); return }
        beginImport()
        importTask = Task { @MainActor in
            let copyTask = Task.detached(priority: .userInitiated) {
                var copied: [URL] = []
                do {
                    for url in urls {
                        try Task.checkCancellation()
                        copied.append(try PersonalMediaFiles.copy(url))
                    }
                    try Task.checkCancellation()
                    return copied
                } catch { PersonalMediaFiles.remove(copied); throw error }
            }
            do {
                let copied = try await withTaskCancellationHandler(operation: { try await copyTask.value }, onCancel: { copyTask.cancel() })
                guard !Task.isCancelled else { PersonalMediaFiles.remove(copied); return }
                loading = false
                play(copied.map { MediaChannel(title: $0.deletingPathExtension().lastPathComponent, url: $0) })
            } catch { finishImportError(error) }
        }
    }

    private func beginImport() { importTask?.cancel(); loading = true; message = nil }
    private func finishImportError(_ error: Error) {
        guard !Task.isCancelled else { return }
        loading = false; photos = []; video = nil
        message = L10n.tr("Medya açılamadı. Dosyanın indirildiğini ve boş alanı kontrol et.")
    }
    private func playPendingMedia() {
        guard !pendingMedia.isEmpty else { return }
        let channels = pendingMedia; pendingMedia = []
        play(channels)
    }
    private func play(_ channels: [MediaChannel]) {
        guard let first = channels.first else { return }
        if model.playMedia(first, queue: channels, advanceAutomatically: true) { showingPlayer = true }
    }
}

/// The presentation owns its copies, including during PhotosPicker's dismissal animation.
/// SwiftUI may temporarily remove the editor view without ending this presentation.
private final class SlideshowSelection: Identifiable {
    let id = UUID()
    let urls: [URL]
    init(urls: [URL]) { self.urls = urls }
    deinit { PersonalMediaFiles.remove(urls) }
}

struct QuickMediaLinkView: View {
    var onPlay: (MediaChannel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    private var url: URL? { try? MediaURL.validate(address) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "link").font(.system(size: 36)).foregroundStyle(MirrorStyle.accent).padding(.top, 12)
                    Text(L10n.tr("Doğrudan video veya ses bağlantısı gir. Web sayfaları burada oynatılamaz."))
                        .font(.body).foregroundStyle(MirrorStyle.secondary)
                    TextField("https://", text: $address)
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit(play)
                        .padding(18).frame(minHeight: 58).background(MirrorStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(L10n.tr("Kaynak adresi")).accessibilityIdentifier("quick-media-url")
                    PasteButton(payloadType: String.self) { values in if let value = values.first { address = value } }
                        .tint(MirrorStyle.accent)
                    if !address.isEmpty && url == nil {
                        Text(L10n.tr("Geçerli bir http veya https bağlantısı gir.")).font(.footnote).foregroundStyle(.orange)
                            .accessibilityIdentifier("quick-media-error")
                    }
                    Button(action: play) { Label(L10n.tr("Oynat"), systemImage: "play.fill") }
                        .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(url == nil)
                        .accessibilityIdentifier("quick-media-play")
                }.padding(24)
            }.background(MirrorStyle.background)
                .navigationTitle(L10n.tr("Bağlantı aç")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Kapat")) { dismiss() } } }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
    private func play() {
        guard let url else { return }
        // Display only the host; URL paths and query parameters can contain access tokens.
        onPlay(MediaChannel(title: url.host ?? L10n.tr("Yayın bağlantısı"), url: url))
        dismiss()
    }
}

private struct SlideshowEditor: View {
    let selection: SlideshowSelection
    private var photos: [URL] { selection.urls }
    var onPlay: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = 5
    @State private var exporting = false
    @State private var progress = 0.0
    @State private var failure = false
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(String(format: L10n.tr("%d fotoğraf"), photos.count)).font(.title2.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, url in
                            SlideshowThumbnail(url: url)
                                .overlay(alignment: .bottomLeading) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).padding(6)
                                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8)).padding(6)
                                }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("Fotoğraf başına")).font(.headline)
                        Picker(L10n.tr("Fotoğraf başına"), selection: $seconds) {
                            ForEach(PhotoSlideshow.intervals, id: \.self) { value in
                                Text(Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated))).tag(value)
                            }
                        }.pickerStyle(.segmented).disabled(exporting)
                    }
                    Text(L10n.tr("Fotoğraflar cihazında 1080p slayta dönüşür. Asılları değişmez."))
                        .font(.footnote).foregroundStyle(MirrorStyle.secondary)
                    if exporting { ProgressView(L10n.tr("Medya hazırlanıyor…"), value: progress).tint(MirrorStyle.accent) }
                    if failure { Text(L10n.tr("Medya açılamadı. Dosyanın indirildiğini ve boş alanı kontrol et.")).font(.footnote).foregroundStyle(.orange) }
                    Button(action: start) { Label(L10n.tr("Slayt gösterisi"), systemImage: "play.fill") }
                        .buttonStyle(MirivoButtonStyle(prominent: true)).disabled(exporting)
                        .accessibilityIdentifier("start-slideshow")
                }.padding(24)
            }.background(MirrorStyle.background)
                .navigationTitle(L10n.tr("Fotoğraflar")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Kapat")) { exportTask?.cancel(); dismiss() }
                } }
        }.tint(MirrorStyle.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
            .onDisappear { exportTask?.cancel() }
    }
    private func start() {
        exporting = true; failure = false; progress = 0
        exportTask = Task { @MainActor in
            let awakeLease = MediaScreenAwake.acquire()
            defer { MediaScreenAwake.release(awakeLease) }
            do {
                let url = try await PhotoSlideshow.export(photos, secondsPerPhoto: seconds) { value in
                    Task { @MainActor in progress = value }
                }
                guard !Task.isCancelled else { PersonalMediaFiles.remove([url]); return }
                onPlay(url); dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                exporting = false; failure = true
            }
        }
    }
}

private struct SlideshowThumbnail: View {
    let url: URL
    @State private var thumbnail: CGImage?
    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() }
                else { ProgressView() }
            }
            .background(MirrorStyle.surface).clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
            .task(id: url) { thumbnail = await Task.detached { PhotoSlideshow.thumbnail(url) }.value }
    }
}
