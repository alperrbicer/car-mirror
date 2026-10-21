import UIKit
import SwiftUI
import AVKit
import CarPlay

/// Only handles screens that iOS actually supplies.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let diagnosticID = UUID()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let screen = scene as? UIWindowScene else { return }
        let role = Self.displayRole(role: session.role, idiom: screen.traitCollection.userInterfaceIdiom)
        let window = UIWindow(windowScene: screen)
        window.rootViewController = UIHostingController(rootView: ExternalDisplayProbeView(model: .shared, isCarPlay: role == .carPlay))
        window.isHidden = false
        self.window = window
        MirrorModel.shared.externalScreenConnected(diagnosticID,
            role: role,
            size: screen.screen.bounds.size)
    }

    static func displayRole(role: UISceneSession.Role, idiom: UIUserInterfaceIdiom) -> DiagnosticValues.Screen {
        // CarPlay Simulator can supply an ordinary external-display scene.
        // Its car idiom still identifies the destination without guessing from size.
        if idiom == .carPlay || role == .carTemplateApplication || role.rawValue == "UIWindowSceneSessionRoleCarPlay" {
            return .carPlay
        }
        return role == .windowExternalDisplayNonInteractive ? .externalNonInteractive : .externalInteractive
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true
        window = nil
        MirrorModel.shared.externalScreenDisconnected(diagnosticID)
    }
}

/// Some iOS CarPlay sessions supply a UIWindowScene rather than the template
/// scene. Own only that otherwise-empty, system-provided car window; never
/// replace the phone, an external-display delegate, or a template scene.
@MainActor
final class CarPlayWindowCoordinator: NSObject {
    static let shared = CarPlayWindowCoordinator()
    private var started = false
    private var presentations: [String: (window: UIWindow, diagnosticID: UUID)] = [:]

    func start() {
        guard !started else { return }
        started = true
        for name in [UIScene.willConnectNotification, UIScene.didActivateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sceneAvailable(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDisconnected(_:)),
                                               name: UIScene.didDisconnectNotification, object: nil)
        UIApplication.shared.connectedScenes.forEach(attach)
    }

    static func shouldAttach(role: UISceneSession.Role, idiom: UIUserInterfaceIdiom,
                             hasDelegate: Bool, hasWindows: Bool) -> Bool {
        idiom == .carPlay && role != .windowApplication && role != .carTemplateApplication &&
            role != .windowExternalDisplayNonInteractive &&
            !hasDelegate && !hasWindows
    }

    @objc private func sceneAvailable(_ notification: Notification) {
        guard let scene = notification.object as? UIScene else { return }
        attach(scene)
    }

    private func attach(_ scene: UIScene) {
        guard let scene = scene as? UIWindowScene else { return }
        let id = scene.session.persistentIdentifier
        guard presentations[id] == nil,
              Self.shouldAttach(role: scene.session.role, idiom: scene.traitCollection.userInterfaceIdiom,
                                hasDelegate: scene.delegate != nil, hasWindows: !scene.windows.isEmpty) else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ExternalDisplayProbeView(model: .shared, isCarPlay: true))
        let diagnosticID = UUID()
        presentations[id] = (window, diagnosticID)
        window.isHidden = false
        MirrorModel.shared.externalScreenConnected(diagnosticID, role: .carPlay, size: scene.screen.bounds.size)
    }

    @objc private func sceneDisconnected(_ notification: Notification) {
        guard let scene = notification.object as? UIScene,
              let presentation = presentations.removeValue(forKey: scene.session.persistentIdentifier) else { return }
        presentation.window.isHidden = true
        presentation.window.rootViewController = nil
        MirrorModel.shared.externalScreenDisconnected(presentation.diagnosticID)
    }
}

struct ExternalDisplayProbeView: View {
    @ObservedObject var model: MirrorModel
    let isCarPlay: Bool
    @ObservedObject private var playback: PlaybackController
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    init(model: MirrorModel, isCarPlay: Bool) {
        self.model = model; self.isCarPlay = isCarPlay; playback = model.playback
    }

    var body: some View {
        Group {
            if isCarPlay {
                displayContent
            } else {
                displayContent.ignoresSafeArea()
            }
        }
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .id(language)
    }

    private var displayContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let started = model.probeStartedAt { ConnectionPatternView(startedAt: started) }
            else if playback.hasActivePlayback && !playback.playsOnPhone && playback.tvDevice == nil {
                ExternalDisplayPlayerView(model: model)
            } else {
                VStack(spacing: 16) {
                    MirrorMark().frame(width: 72, height: 72)
                    Text(BrandIdentity.name).font(.largeTitle)
                    Text(L10n.tr(playback.playsOnPhone ? "Telefonda oynatılıyor" : isCarPlay ? "CarPlay bağlı" : "iPhone’da ekran paylaşımını başlat.")).foregroundStyle(.secondary)
                    if playback.playsOnPhone, playback.hasActivePlayback {
                        Button(L10n.tr("Bu ekranda oynat")) { model.returnToDisplay() }
                            .buttonStyle(.borderedProminent).tint(MirrorStyle.accent).foregroundStyle(.black)
                    } else if let message = model.mediaErrorMessage {
                        Text(message).font(.subheadline).multilineTextAlignment(.center)
                        Button(L10n.tr("Yeniden dene")) { model.retryMedia() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

/// Controls live in the system-provided video window and adapt to its available area.
struct ExternalDisplayPlayerView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback: PlaybackController
    @ObservedObject private var favorites = MediaFavorites.shared
    @AppStorage("player.externalVideoDisplayMode") private var displayMode = PlayerVideoDisplayMode.normal
    @State private var controlsVisible = true
    @State private var showingChannels = false
    @State private var favoritesOnly = false
    @State private var favoriteSeries: MediaSeries?
    @State private var browsingCategories = false
    @State private var browsingSeries: MediaSeries?
    @State private var selectedCategoryName: String?
    @State private var sourceCategories: [MediaChannelCategory] = []
    @State private var selectedSourceCatalog: MediaSeriesCatalog?
    @State private var catalogLoading = false
    @State private var catalogError: String?
    @State private var catalogRequestID = UUID()
    @State private var catalogTask: Task<Void, Never>?
    @State private var loadingFavorite = false
    @State private var favoriteError: String?
    @State private var scrubbing = false
    @State private var hideTask: Task<Void, Never>?

    init(model: MirrorModel) { self.model = model; playback = model.playback }
    private var queueTitle: String { model.selectedMediaChannel?.episode == nil ? "Kanallar" : "Bölümler" }
    private var portraitScreenShare: Bool {
        guard model.broadcasting, let capture = model.capture,
              let width = capture.videoWidth, let height = capture.videoHeight else { return false }
        return height > width
    }
    private var channels: [MediaChannel] {
        favoriteSeries?.channels ?? model.playbackQueue
    }
    private var favoriteItems: [FavoriteMedia] { favorites.entries.filter { $0.sourceID == model.playbackSourceID } }
    private var externalDisplayMode: PlayerVideoDisplayMode {
        displayMode == .fillScreen ? .fitScreen : displayMode
    }
    private var selectedSourceCategory: MediaChannelCategory? {
        guard let selectedCategoryName else { return nil }
        return sourceCategories.first { $0.id == selectedCategoryName }
    }
    private var categoryPanelTitle: String {
        browsingSeries?.title ?? selectedSourceCategory.map { $0.name.isEmpty ? L10n.tr("Diğer kanallar") : $0.name }
            ?? L10n.tr("Kategoriler")
    }
    private var panelScrollIdentity: String {
        if browsingCategories {
            if let browsingSeries { return "category-series-\(browsingSeries.id)" }
            if let selectedCategoryName { return "category-items-\(selectedCategoryName)" }
            return "categories"
        }
        if favoritesOnly { return favoriteSeries.map { "favorite-series-\($0.id)" } ?? "favorites" }
        return "playback-queue"
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MediaVideoView(playback: playback, role: .external, displayMode: externalDisplayMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                Color.clear.contentShape(Rectangle()).onTapGesture {
                    controlsVisible.toggle(); scheduleHide()
                }
                if controlsVisible || showingChannels {
                    LinearGradient(colors: [.black.opacity(0.72), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Text(model.mediaTitle ?? L10n.tr("iPhone ekranı"))
                                .font(.headline).lineLimit(1)
                            Spacer(minLength: 0)
                            if let channel = model.selectedMediaChannel {
                                MediaFavoriteButton(channel: channel, sourceID: model.playbackSourceID)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 22) {
                            if !showingChannels && !model.broadcasting && model.playbackQueue.count > 1 {
                                transport("backward.end.fill", title: "Önceki", id: "external-previous") { model.switchChannel(-1) }
                                    .disabled(model.adjacentChannel(-1) == nil)
                            }
                            transport(playback.isPlaying ? "pause.fill" : "play.fill", title: playback.isPlaying ? "Duraklat" : "Oynat", id: "external-play-pause") {
                                playback.togglePlayPause()
                            }
                            if !showingChannels && !model.broadcasting && model.playbackQueue.count > 1 {
                                transport("forward.end.fill", title: "Sonraki", id: "external-next") { model.switchChannel(1) }
                                    .disabled(model.adjacentChannel(1) == nil)
                            }
                        }
                        Spacer(minLength: 0)
                        if model.selectedMediaChannel != nil {
                            PlaybackTimelineView(playback: playback) { scrubbing = $0; scheduleHide() }
                                .id(model.selectedMediaChannel?.id)
                        }
                        HStack {
                            if !model.broadcasting, model.selectedMediaChannel != nil {
                                Button { showingChannels.toggle(); scheduleHide() } label: {
                                    Label(L10n.tr(queueTitle), systemImage: "list.bullet")
                                }.accessibilityIdentifier("external-channels")
                            }
                            Spacer()
                            if !portraitScreenShare {
                                Button {
                                    displayMode = externalDisplayMode == .fitScreen ? .normal : .fitScreen
                                    scheduleHide()
                                } label: {
                                    Label(L10n.tr(externalDisplayMode == .fitScreen ? "Normal" : "Sığdır"), systemImage: "aspectratio")
                                }.accessibilityIdentifier("external-display-mode")
                            }
                        }.font(.body.weight(.semibold)).buttonStyle(.bordered)
                            .tint(.white).controlSize(.large)
                    }
                    .padding(.horizontal, max(20, geometry.safeAreaInsets.leading))
                    .padding(.top, max(8, geometry.safeAreaInsets.top))
                    .padding(.bottom, max(12, geometry.safeAreaInsets.bottom))
                }
                if playback.state == .loading {
                    ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
                }
                if showingChannels && !model.broadcasting {
                    channelPanel.frame(width: min(480, geometry.size.width * 0.48))
                        .frame(height: max(0, geometry.size.height - 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.foregroundStyle(.white)
                .background(.black)
                .accessibilityIdentifier("external-video-player")
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task(id: model.selectedMediaChannel?.id) { await model.restorePlaybackQueueFromSource(); scheduleHide() }
        .onChange(of: playback.isPlaying) { _, _ in controlsVisible = true; scheduleHide() }
        .onChange(of: favoritesOnly) { _, _ in favoriteSeries = nil }
        .onChange(of: model.playbackSourceID) { _, _ in
            catalogTask?.cancel()
            catalogTask = nil
            catalogRequestID = UUID()
            catalogLoading = false
            catalogError = nil
            sourceCategories = []
            selectedSourceCatalog = nil
            browsingCategories = false
            browsingSeries = nil
            selectedCategoryName = nil
        }
        .alert(BrandIdentity.name, isPresented: Binding(get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } })) {
            Button(L10n.tr("Tamam")) { favoriteError = nil }
        } message: { Text(favoriteError ?? "") }
        .onDisappear { hideTask?.cancel(); catalogTask?.cancel() }
    }

    private var channelPanel: some View {
        VStack(spacing: 12) {
            HStack {
                if browsingCategories {
                    Button { goBackInCategories() } label: {
                        Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Geri"))
                    Text(categoryPanelTitle).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                } else if let favoriteSeries {
                    Button { self.favoriteSeries = nil } label: {
                        Label(L10n.tr("Favoriler"), systemImage: "chevron.backward").frame(minHeight: 44)
                    }
                    Text(favoriteSeries.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                } else {
                    Picker(L10n.tr("Oynatma listesi"), selection: $favoritesOnly) {
                        Text(L10n.tr(queueTitle)).tag(false)
                        Text(L10n.tr("Favoriler")).tag(true)
                    }.pickerStyle(.segmented)
                    Button { showSourceCategories() } label: {
                        Image(systemName: "square.grid.2x2").frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.tr("Kategoriler"))
                }
                Button { showingChannels = false; scheduleHide() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel(L10n.tr("Kapat"))
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    if browsingCategories {
                        if let browsingSeries {
                            ForEach(browsingSeries.channels) { channel in
                                categoryChannelCard(channel, queue: browsingSeries.channels)
                            }
                        } else if selectedCategoryName != nil, let selectedSourceCatalog {
                            ForEach(selectedSourceCatalog.series) { series in
                                categorySeriesCard(series)
                            }
                            ForEach(selectedSourceCatalog.ungrouped) { channel in
                                categoryChannelCard(channel, queue: selectedSourceCategory?.channels ?? [])
                            }
                        } else if catalogLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        } else if !sourceCategories.isEmpty {
                            ForEach(sourceCategories) { category in
                                categoryCard(category)
                            }
                        } else if let catalogError {
                            Text(catalogError).font(.subheadline).foregroundStyle(.secondary).padding()
                        } else {
                            Text(L10n.tr("İçerik bulunamadı")).font(.subheadline).foregroundStyle(.secondary).padding()
                        }
                    } else if favoritesOnly && favoriteSeries == nil {
                        ForEach(favoriteItems) { item in
                            Button { Task { await openFavorite(item) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    MediaArtworkView(channel: item.channel, cornerRadius: 10).aspectRatio(16 / 9, contentMode: .fit)
                                    Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    if item.series != nil || item.channel.episode != nil {
                                        Text(L10n.tr(item.series != nil ? "Dizi" : "Bölüm")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(loadingFavorite)
                        }
                    } else {
                      ForEach(channels) { channel in
                        Button {
                            _ = model.playMedia(channel, queue: channels, sourceID: model.playbackSourceID)
                            showingChannels = false; controlsVisible = true; scheduleHide()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                MediaArtworkView(channel: channel, cornerRadius: 10)
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topLeading) {
                                        if channel.id == model.selectedMediaChannel?.id {
                                            Image(systemName: "waveform").padding(6).background(MirrorStyle.accent, in: Capsule()).foregroundStyle(.black).padding(5)
                                        }
                                    }
                                Text(channelPanelTitle(for: channel))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                      }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
                if loadingFavorite { ProgressView().padding() }
                if favoritesOnly && favoriteSeries == nil && favoriteItems.isEmpty {
                    Text(L10n.tr("Sevdiğin içerikleri kalp düğmesiyle buraya ekle.")).font(.subheadline).padding()
                }
            }
            .id(panelScrollIdentity)
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(8)
        .accessibilityIdentifier("external-channel-panel")
    }

    private func categoryCard(_ category: MediaChannelCategory) -> some View {
        Button {
            selectedCategoryName = category.id
            selectedSourceCatalog = MediaSeriesCatalog(category.channels)
            browsingSeries = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let channel = category.channels.first {
                    MediaArtworkView(channel: channel, cornerRadius: 10)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name)
                    .font(.subheadline.weight(.medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: L10n.tr("%d içerik"), category.channels.count))
                    .font(.caption).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func categorySeriesCard(_ series: MediaSeries) -> some View {
        Button { browsingSeries = series } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let channel = series.artworkChannel {
                    MediaArtworkView(channel: channel, cornerRadius: 10)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(series.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.tr("Dizi")).font(.caption).foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func categoryChannelCard(_ channel: MediaChannel, queue: [MediaChannel]) -> some View {
        Button {
            let playbackQueue = MediaSeriesCatalog.playbackQueue(for: channel, in: queue)
            _ = model.playMedia(channel, queue: playbackQueue, sourceID: model.playbackSourceID)
            showingChannels = false
            controlsVisible = true
            scheduleHide()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                MediaArtworkView(channel: channel, cornerRadius: 10)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(channelPanelTitle(for: channel))
                    .font(.subheadline.weight(.medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func showSourceCategories() {
        favoritesOnly = false
        favoriteSeries = nil
        browsingCategories = true
        browsingSeries = nil
        selectedCategoryName = nil
        selectedSourceCatalog = nil
        catalogError = nil
        catalogTask?.cancel()
        catalogTask = nil
        let requestID = UUID()
        catalogRequestID = requestID
        let sourceID = model.playbackSourceID
        guard let sourceID,
              let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) else {
            sourceCategories = MediaChannelCategory.group(model.playbackQueue)
            catalogLoading = false
            return
        }
        if let cached = SourceLibrary.shared.cachedChannels(for: source) {
            sourceCategories = MediaChannelCategory.group(cached)
            catalogLoading = false
            if cached.isEmpty { catalogError = L10n.tr("İçerik bulunamadı") }
            return
        }
        sourceCategories = []
        catalogLoading = true
        catalogTask = Task { @MainActor in
            defer {
                if self.catalogRequestID == requestID {
                    self.catalogLoading = false
                    self.catalogTask = nil
                }
            }
            do {
                let loaded = try await SourceLibrary.shared.channels(for: source)
                guard !Task.isCancelled, self.catalogRequestID == requestID,
                      self.model.playbackSourceID == sourceID else { return }
                self.sourceCategories = MediaChannelCategory.group(loaded)
                if loaded.isEmpty { self.catalogError = L10n.tr("İçerik bulunamadı") }
            } catch {
                guard !Task.isCancelled, self.catalogRequestID == requestID,
                      self.model.playbackSourceID == sourceID else { return }
                self.catalogError = L10n.tr("İçerikler yüklenemedi.")
            }
        }
    }

    private func goBackInCategories() {
        if browsingSeries != nil { browsingSeries = nil }
        else if selectedCategoryName != nil {
            selectedCategoryName = nil
            selectedSourceCatalog = nil
        }
        else { browsingCategories = false }
    }
    private func channelPanelTitle(for channel: MediaChannel) -> String {
        guard let episode = channel.episode else { return channel.title }
        let number = SeriesText.episode(episode)
        guard let title = episode.resolvedTitle(providerTitle: channel.metadata.episodeTitle) else { return number }
        return number + " · " + title
    }
    @MainActor private func openFavorite(_ item: FavoriteMedia) async {
        guard !loadingFavorite else { return }
        loadingFavorite = true
        defer { loadingFavorite = false }
        do {
            let source = SourceLibrary.shared.sources.first { $0.id == item.sourceID }
            let catalog: [MediaChannel]
            if let source { catalog = try await SourceLibrary.shared.channels(for: source) }
            else { catalog = item.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID) }
            if item.series != nil {
                favoriteSeries = item.resolveSeries(in: catalog)
                if favoriteSeries == nil { favoriteError = L10n.tr("İçerik bulunamadı") }
            } else {
                if model.playMedia(item.channel, queue: MediaSeriesCatalog.playbackQueue(for: item.channel, in: catalog), sourceID: item.sourceID) {
                    showingChannels = false; controlsVisible = true; scheduleHide()
                }
            }
        } catch { favoriteError = L10n.tr("İçerikler yüklenemedi.") }
    }
    private func transport(_ symbol: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button { action(); controlsVisible = true; scheduleHide() } label: {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
                .frame(width: 64, height: 64).background(.black.opacity(0.4), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(L10n.tr(title)).accessibilityIdentifier(id)
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard playback.isPlaying, !showingChannels, !scrubbing, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            controlsVisible = false
        }
    }
}

struct ConnectionPatternView: View {
    let startedAt: Date
    private let colors: [Color] = [.white, .yellow, .cyan, .green, Color(red: 1, green: 0, blue: 1), .red, .blue]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let progress = CGFloat(elapsed.truncatingRemainder(dividingBy: 3) / 3)
            GeometryReader { geometry in
                ZStack {
                    MirrorStyle.background
                    VStack(spacing: 18) {
                        Text(BrandIdentity.name).font(.system(size: 22, weight: .medium))
                        Text(String(format: "%06.2f", elapsed))
                            .font(.system(size: min(geometry.size.width / 6, geometry.size.height / 4), weight: .medium, design: .monospaced))
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in colors[index] }
                        }
                        .frame(width: geometry.size.width * 0.6, height: 20)
                    }
                    Circle()
                        .fill(MirrorStyle.accent)
                        .frame(width: 18, height: 18)
                        .position(x: 30 + (geometry.size.width - 60) * progress,
                                  y: geometry.size.height * 0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel(L10n.tr("Hareketli ekran bağlantı testi"))
    }
}
