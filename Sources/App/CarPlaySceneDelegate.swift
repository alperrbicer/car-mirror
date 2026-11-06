import CarPlay
import UIKit
import Combine

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate, CPInterfaceControllerDelegate {
    private var controller: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private var list: CPListTemplate?
    private var menuUpdates: AnyCancellable?
    private var catalogUpdates: AnyCancellable?
    private var hasPlaybackControls = false
    private let catalogRequest = CarPlayCatalogRequest()
    private let playbackTransition = CarPlayPlaybackTransition()
    private weak var favoritesList: CPListTemplate?
    private var favoritesOffset = 0
    private var categoryArtworkTasks: [UUID: Task<Void, Never>] = [:]
    // The system maximum is larger than the number of cards this CarPlay row
    // renders at once, so chunk to the visible seven-card width.
    private let artworkCardsPerRow = 7

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.connected(sessionID: scene.session.persistentIdentifier)
        controller = interfaceController
        interfaceController.delegate = self
        configuration = CPSessionConfiguration(delegate: self)
        let home = CPListTemplate(title: BrandIdentity.name, sections: [])
        list = home
        let sources = SourceLibrary.shared.sources
        let root = sources.isEmpty ? home : CPListTemplate(title: nil, sections: [])
        if root !== home {
            configureLibraryNavigation(root)
            if sources.count == 1 { root.emptyViewTitleVariants = [L10n.tr("Kaynak yükleniyor…")] }
        }
        MirrorModel.shared.connected(supportsVideo: supportsVideo)
        render()
        interfaceController.setRootTemplate(root, animated: false) { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.controller === interfaceController else { return }
                let model = MirrorModel.shared
                if success {
                    model.record(.carTemplateReady)
                    if model.prepareCarPlayNowPlaying() {
                        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: false) { [weak self] _, error in
                            if let error { self?.recordTemplateError(error) }
                        }
                    }
                    if sources.count == 1, let source = sources.first {
                        self.openSource(source, replacing: root, completion: {})
                    } else if !sources.isEmpty {
                        self.showSources(replacing: root)
                    }
                }
                else if let error {
                    var values = DiagnosticValues()
                    values.screen = .carPlay
                    values.failure = DiagnosticFailure(error)
                    model.record(.failure, values: values)
                    model.errorMessage = error.localizedDescription
                }
            }
        }
        let catalogChanges = Self.catalogChanges(library: .shared, favorites: .shared).share()
        menuUpdates = Self.menuChanges(model: .shared).merge(with: catalogChanges)
            .debounce(for: .milliseconds(20), scheduler: RunLoop.main)
            .sink { [weak self] in self?.render() }
        catalogUpdates = catalogChanges
            .debounce(for: .milliseconds(20), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, let favoritesList = self.favoritesList else { return }
                self.showFavorites(offset: self.favoritesOffset, replacing: favoritesList)
            }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.disconnected(sessionID: scene.session.persistentIdentifier)
        menuUpdates = nil
        interfaceController.delegate = nil
        catalogUpdates = nil
        hasPlaybackControls = false
        catalogRequest.cancel()
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()
        playbackTransition.cancel()
        list = nil
        favoritesList = nil
        favoritesOffset = 0
        MirrorModel.shared.disconnected()
        controller = nil
        configuration = nil
    }

    func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        if let template = aTemplate as? CPListTemplate {
            CarPlayPlaybackTransition.resetSelections(in: template)
        }
    }

    private func render() {
        guard list != nil, controller != nil else { return }
        let model = MirrorModel.shared

        var items: [CPListItem] = []
        if model.requiresMembership {
            let pro = CPListItem(text: L10n.tr("Mirivo Pro"), detailText: L10n.tr("Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir."), image: UIImage(systemName: "lock"))
            pro.handler = { [weak self] _, completion in
                model.presentMembershipOffer()
                self?.showError(L10n.tr("Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir."))
                completion()
            }
            items.append(pro)
        }
        if supportsVideo {
            let mirror = CPListItem(text: L10n.tr("iPhone ekranı"), detailText: model.captureTitle,
                                    image: UIImage(systemName: "iphone.radiowaves.left.and.right"))
            mirror.isEnabled = model.readyToPlay && model.supportsVideo == true
            if #available(iOS 26.4, *) {
                mirror.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            mirror.handler = { _, completion in
                model.playOnDisplay()
                completion()
            }
            items.append(mirror)
        }
        let sources = CPListItem(text: L10n.tr("Kaynaklar"), detailText: nil, image: UIImage(systemName: "play.rectangle.on.rectangle"))
        sources.isEnabled = !SourceLibrary.shared.sources.isEmpty
        sources.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            let sources = SourceLibrary.shared.sources
            if sources.count == 1, let source = sources.first {
                self.openSource(source, completion: completion)
            } else {
                self.showSources()
                completion()
            }
        }
        items.append(sources)
        let favorites = CPListItem(text: L10n.tr("Favoriler"),
                                   detailText: String(format: L10n.tr("%d içerik"), MediaFavorites.shared.entries.count),
                                   image: UIImage(systemName: "heart.fill"))
        favorites.handler = { [weak self] _, completion in self?.showFavorites(); completion() }
        items.append(favorites)
        let stop = CPListItem(text: L10n.tr(model.mediaTitle == nil ? "Paylaşımı durdur" : "Oynatmayı durdur"), detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting || model.probeStartedAt != nil || model.mediaTitle != nil
        stop.handler = { _, completion in model.stopBroadcast(hideSavedPlaybackBar: true); model.stopProbe(); model.stopPlayback(); completion() }
        if stop.isEnabled || supportsVideo { items.append(stop) }
        #if DEBUG
        if supportsVideo {
            let probe = CPListItem(text: L10n.tr("Ekran bağlantı testi"), detailText: nil, image: UIImage(systemName: "display"))
            probe.isEnabled = model.supportsVideo == true && !model.broadcasting
            if #available(iOS 26.4, *) {
                probe.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            probe.handler = { _, completion in model.startVideoProbe(); completion() }
            items.append(probe)
        }
        #endif
        list?.updateSections([CPListSection(items: items)])
        let hasPlayback = model.mediaTitle != nil
        if hasPlayback != hasPlaybackControls {
            hasPlaybackControls = hasPlayback
            if let list { updateNavigationButtons(list) }
            controller?.templates.compactMap { $0 as? CPListTemplate }.filter { $0 !== list }
                .forEach(updateNavigationButtons)
        }
    }

    private var supportsVideo: Bool {
        if #available(iOS 26.4, *) { return configuration?.supportsVideoPlayback == true }
        return false
    }

    /// Observe menu inputs, not playback ticks or capture statistics. Delivery is
    /// deferred so @Published's willSet notifications never render the old value.
    private static func menuChanges(model: MirrorModel) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            model.$sessionState.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$capture.map { $0?.canPlay() == true }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$supportsVideo.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$probeStartedAt.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$mediaTitle.map { $0 != nil }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$requiresMembership.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]).eraseToAnyPublisher()
    }

    /// Playback changes must not replace selectable favorite rows or their handlers.
    private static func catalogChanges(library: SourceLibrary, favorites: MediaFavorites) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            library.$sources.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            favorites.$entries.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in L10n.language }.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]).eraseToAnyPublisher()
    }

    private func push(_ template: CPTemplate) {
        if let template = template as? CPListTemplate { configureLibraryNavigation(template) }
        controller?.pushTemplate(template, animated: true) { [weak self] _, error in
            if let error { self?.recordTemplateError(error) }
        }
    }

    private func updateNavigationButtons(_ template: CPListTemplate) {
        // Keep the same controls on series, film, and live catalog lists.
        // CarPlay lays trailing buttons from the edge inward, so Home appears
        // before Stop as in the shared playback header.
        template.leadingNavigationBarButtons = [
            CPBarButton(title: L10n.tr("Favoriler")) { [weak self] _ in self?.showFavorites() }
        ]
        let stop = CPBarButton(image: UIImage(systemName: "stop.fill")!) { _ in
            MirrorModel.shared.stopPlayback(hideSavedPlaybackBar: true)
        }
        stop.isEnabled = MirrorModel.shared.mediaTitle != nil

        let home = CPBarButton(image: UIImage(systemName: "house")!) { [weak self] _ in
            self?.showHome()
        }
        template.trailingNavigationBarButtons = [home, stop]
    }

    private func configureLibraryNavigation(_ template: CPListTemplate) {
        updateNavigationButtons(template)
    }

    private func showHome() {
        catalogRequest.cancel()
        guard let controller, let list, controller.topTemplate !== list else { return }
        if controller.templates.contains(where: { $0 === list }) {
            controller.pop(to: list, animated: true) { [weak self] _, error in
                if let error { self?.recordTemplateError(error) }
            }
        } else {
            // Home starts a fresh navigation path, keeping room for source,
            // category, channel and Now Playing templates in CarPlay's stack.
            controller.setRootTemplate(list, animated: true) { [weak self] _, error in
                if let error { self?.recordTemplateError(error) }
            }
        }
    }

    private func recordTemplateError(_ error: Error) {
        CarPlayPlaybackTrace.record("template-error \((error as NSError).domain) \((error as NSError).code)")
        var values = DiagnosticValues()
        values.screen = .carPlay
        values.failure = DiagnosticFailure(error)
        MirrorModel.shared.record(.failure, values: values)
    }

    private func showLibraryRoot(_ template: CPListTemplate) {
        // Sources/categories are destinations, rather than another step above
        // Home. Making them the root removes CarPlay's automatic Back button.
        configureLibraryNavigation(template)
        controller?.setRootTemplate(template, animated: true) { [weak self] _, error in
            if let error { self?.recordTemplateError(error) }
        }
    }

    private func showSources(offset: Int = 0, replacing: CPListTemplate? = nil) {
        catalogRequest.cancel()
        let sources = SourceLibrary.shared.sources
        let template = replacing ?? CPListTemplate(title: L10n.tr("Kaynaklar"), sections: [])
        configureLibraryNavigation(template)
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = sources.dropFirst(offset).prefix(pageSize).map { source in
            let item = CPListItem(text: source.name, detailText: nil)
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                self.openSource(source, completion: completion)
            }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showSources(offset: max(0, offset - pageSize), replacing: template)
                completion()
            }
            items.insert(previous, at: 0)
        }
        if sources.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Diğer kaynaklar"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showSources(offset: offset + pageSize, replacing: template)
                completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { showLibraryRoot(template) }
    }

    private func openSource(_ source: MediaSource, replacing: CPListTemplate? = nil, completion: @escaping () -> Void) {
        catalogRequest.start(load: { cached in
            try await SourceLibrary.shared.channels(for: source, onCached: cached)
        }, show: { [weak self] channels in
            self?.showCategories(MediaChannelCategory.group(channels), sourceID: source.id, replacing: replacing)
        }, failure: { [weak self] in
            if let replacing {
                let retry = CPListItem(text: L10n.tr("Yeniden dene"), detailText: nil)
                retry.handler = { [weak self, weak replacing] _, completion in
                    guard let self, let replacing else { completion(); return }
                    self.openSource(source, replacing: replacing, completion: completion)
                }
                replacing.updateSections([CPListSection(items: [retry])])
            }
            self?.showError("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.")
        }, completion: completion)
    }

    private func showCategories(_ categories: [MediaChannelCategory], sourceID: UUID,
                                offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: nil, sections: [])
        template.emptyViewTitleVariants = [L10n.tr("İçerik bulunamadı")]
        configureLibraryNavigation(template)
        if #available(iOS 26.0, *) {
            showArtworkCategories(categories, sourceID: sourceID, offset: offset, replacing: replacing, template: template)
            return
        }
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = categories.dropFirst(offset).prefix(pageSize).map { category in
            let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
            let item = CPListItem(text: name,
                                  detailText: String(format: L10n.tr("%d içerik"), uniqueCatalogEntries(category.channels).count),
                                  image: UIImage(systemName: "folder"))
            item.handler = { [weak self] _, completion in
                self?.showCatalog(category.channels, title: name, sourceID: sourceID)
                completion()
            }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showCategories(categories, sourceID: sourceID,
                                     offset: max(0, offset - pageSize), replacing: template)
                completion()
            }
            items.insert(previous, at: 0)
        }
        if categories.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Sonraki"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showCategories(categories, sourceID: sourceID,
                                     offset: offset + pageSize, replacing: template)
                completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { showLibraryRoot(template) }
    }

    @available(iOS 26.0, *)
    private func showArtworkCategories(_ categories: [MediaChannelCategory], sourceID: UUID,
                                       offset: Int, replacing: CPListTemplate?, template: CPListTemplate) {
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()
        let visibleCategories = Array(categories.dropFirst(offset))
        let page = visibleCategories
        var sections: [CPListSection] = []
        for category in page {
            let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
            let entries = uniqueCatalogEntries(category.channels)
            let channels = entries.filter { $0.metadata.artworkURL != nil }
                .reduce(into: ([MediaChannel](), Set<URL>())) { result, channel in
                    guard let url = channel.metadata.artworkURL, result.1.insert(url).inserted else { return }
                    result.0.append(channel)
                }.0
            guard !channels.isEmpty else { continue }
            let row = CPListImageRowItem(text: nil, cardElements: [], allowsMultipleLines: false)
            row.listImageRowHandler = { [weak self] _, _, completion in
                self?.showCatalog(category.channels, title: name, sourceID: sourceID)
                completion()
            }
            let categoryItem = CPListItem(text: "\(name) · \(entries.count)", detailText: nil,
                                          image: UIImage(systemName: "folder"))
            categoryItem.accessoryType = .disclosureIndicator
            categoryItem.handler = { [weak self] _, completion in
                self?.showCatalog(category.channels, title: name, sourceID: sourceID)
                completion()
            }
            sections.append(CPListSection(items: [categoryItem, row]))
            // Render a complete row on the first frame. Artwork downloads then
            // replace these placeholders in place instead of inserting cards later.
            row.elements = channels.prefix(artworkCardsPerRow).map { channel in
                let image = channel.metadata.artworkURL.flatMap {
                    MediaArtworkStore.shared.cachedImage(at: $0, maximumPixelSize: 240)
                } ?? UIImage(systemName: channel.isAudio ? "waveform" : "film") ?? UIImage()
                return CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                     title: channel.title, subtitle: nil, tintColor: nil)
            }
            let taskID = UUID()
            categoryArtworkTasks[taskID] = Task { @MainActor [weak self, weak row] in
                guard let self, let row else { return }
                var cards: [CPListImageRowItemCardElement] = []
                for channel in channels.prefix(artworkCardsPerRow) {
                    guard !Task.isCancelled else { return }
                    let image: UIImage
                    if let artwork = channel.metadata.artworkURL,
                       let loaded = await MediaArtworkStore.shared.image(at: artwork, maximumPixelSize: 240) {
                        image = loaded
                    } else {
                        image = UIImage(systemName: channel.isAudio ? "waveform" : "film") ?? UIImage()
                    }
                    guard !Task.isCancelled else { return }
                    cards.append(CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                               title: channel.title, subtitle: nil, tintColor: nil))
                }
                guard !Task.isCancelled else { return }
                row.elements = cards
                self.categoryArtworkTasks.removeValue(forKey: taskID)
            }
        }
        template.updateSections(sections)
        if replacing == nil { showLibraryRoot(template) }
    }

    private func showFavorites(offset: Int = 0, replacing: CPListTemplate? = nil) {
        if replacing == nil {
            catalogRequest.cancel()
            if let controller, let favoritesList, controller.templates.contains(where: { $0 === favoritesList }) {
                if controller.topTemplate !== favoritesList {
                    controller.pop(to: favoritesList, animated: true) { [weak self] _, error in
                        if let error { self?.recordTemplateError(error) }
                    }
                }
                return
            }
        }
        let template = replacing ?? CPListTemplate(title: L10n.tr("Favoriler"), sections: [])
        favoritesList = template
        if #available(iOS 26.0, *) {
            favoritesOffset = 0
            showArtworkFavorites(template, entries: MediaFavorites.shared.entries,
                sourceNames: Dictionary(uniqueKeysWithValues: SourceLibrary.shared.sources.map { ($0.id, $0.name) }))
            if replacing == nil { push(template) }
            return
        }
        favoritesOffset = CarPlayFavoritesMenu.update(template, entries: MediaFavorites.shared.entries,
            sourceNames: Dictionary(uniqueKeysWithValues: SourceLibrary.shared.sources.map { ($0.id, $0.name) }),
            offset: offset, supportsVideo: supportsVideo,
            open: { [weak self] item, completion in
                guard let self else { completion(false); return }
                self.openFavorite(item, completion: completion)
            }, page: { [weak self, weak template] page in
                guard let template else { return }
                self?.showFavorites(offset: page, replacing: template)
            })
        if replacing == nil { push(template) }
    }

    @available(iOS 26.0, *)
    private func showArtworkFavorites(_ template: CPListTemplate, entries: [FavoriteMedia],
                                      sourceNames: [UUID: String]) {
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()
        template.emptyViewTitleVariants = [L10n.tr("Favoriler")]
        template.emptyViewSubtitleVariants = [L10n.tr("Sevdiğin içerikleri kalp düğmesiyle buraya ekle.")]

        let items = entries.map { favorite -> (favorite: FavoriteMedia, artwork: MediaChannel, subtitle: String) in
            let posterChannel: MediaChannel
            if favorite.series != nil {
                let source = favorite.sourceID.flatMap { id in SourceLibrary.shared.sources.first { $0.id == id } }
                let cached = source.flatMap { SourceLibrary.shared.cachedChannels(for: $0) }
                    ?? favorite.fallbackCatalog(currentChannels: MirrorModel.shared.playbackQueue,
                                                sourceID: MirrorModel.shared.playbackSourceID)
                posterChannel = favorite.resolveSeries(in: cached)?.artworkChannel ?? favorite.channel
            } else {
                posterChannel = favorite.channel
            }
            let kind = favorite.series != nil ? "Dizi" : favorite.channel.episode != nil ? "Bölüm"
                : favorite.channel.isLive ? "Canlı yayın" : favorite.channel.isAudio ? "Ses"
                : favorite.channel.isMovie ? "Film" : "Video"
            let sourceName = favorite.sourceID.flatMap { sourceNames[$0] }
            let subtitle = [L10n.tr(kind), sourceName].compactMap { $0 }.joined(separator: " · ")
            return (favorite, posterChannel, subtitle)
        }
        let rows = stride(from: 0, to: items.count, by: artworkCardsPerRow).map { start -> (CPListImageRowItem, [(favorite: FavoriteMedia, artwork: MediaChannel, subtitle: String)]) in
            let rowItems = Array(items[start..<min(start + artworkCardsPerRow, items.count)])
            let row = CPListImageRowItem(text: nil, cardElements: [], allowsMultipleLines: false)
            row.elements = rowItems.map { entry in
                let image = entry.artwork.metadata.artworkURL.flatMap {
                    MediaArtworkStore.shared.cachedImage(at: $0, maximumPixelSize: 300)
                } ?? UIImage(systemName: entry.favorite.channel.isLive ? "tv" : "film") ?? UIImage()
                return CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                    title: entry.favorite.title, subtitle: entry.subtitle, tintColor: nil)
            }
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard let self, rowItems.indices.contains(index) else { completion(); return }
                self.openFavorite(rowItems[index].favorite) { _ in completion() }
            }
            return (row, rowItems)
        }
        let countLabel = String(format: L10n.tr("%d içerik"), entries.count)
        template.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows.map(\.0), header: countLabel, sectionIndexTitle: nil)])

        for (row, rowItems) in rows {
            let taskID = UUID()
            categoryArtworkTasks[taskID] = Task { @MainActor [weak self, weak row] in
                guard let self, let row else { return }
                var cards: [CPListImageRowItemCardElement] = []
                for entry in rowItems {
                    guard !Task.isCancelled else { return }
                    let image: UIImage
                    if let artwork = entry.artwork.metadata.artworkURL,
                       let loaded = await MediaArtworkStore.shared.image(at: artwork, maximumPixelSize: 300) {
                        image = loaded
                    } else {
                        image = UIImage(systemName: entry.favorite.channel.isLive ? "tv" : "film") ?? UIImage()
                    }
                    guard !Task.isCancelled else { return }
                    cards.append(CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                        title: entry.favorite.title, subtitle: entry.subtitle, tintColor: nil))
                }
                guard !Task.isCancelled else { return }
                row.elements = cards
                self.categoryArtworkTasks.removeValue(forKey: taskID)
            }
        }
    }

    private func openFavorite(_ favorite: FavoriteMedia, completion: @escaping (Bool) -> Void) {
        catalogRequest.cancel()
        let model = MirrorModel.shared
        let source = SourceLibrary.shared.sources.first { $0.id == favorite.sourceID }
        if favorite.series == nil {
            let channels = source.flatMap { SourceLibrary.shared.cachedChannels(for: $0) }
                ?? favorite.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID)
            completion(play(favorite.channel, channels: channels, sourceID: favorite.sourceID))
            return
        }
        guard source != nil || favorite.sourceID == nil else {
            showError("İçerik bulunamadı")
            completion(false)
            return
        }
        catalogRequest.start(load: { cached in
            if let source {
                return try await SourceLibrary.shared.channels(for: source) { channels in
                    // A favorite missing from an older cache may exist in the refresh.
                    if let series = favorite.resolveSeries(in: channels) { cached(series.channels) }
                }
            }
            return favorite.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID)
        }, show: { [weak self] channels in
            guard let self else { return }
            guard let series = favorite.resolveSeries(in: channels) else {
                self.showError("İçerik bulunamadı"); return
            }
            self.showSeriesSeasons(series, sourceID: favorite.sourceID)
        }, failure: { [weak self] in
            self?.showError("İçerikler yüklenemedi.")
        }, completion: { completion(false) })
    }

    private func play(_ channel: MediaChannel, channels: [MediaChannel], sourceID: UUID?) -> Bool {
        CarPlayPlaybackTrace.record("list-selection video=\(supportsVideo && !channel.isAudio)")
        guard let controller else { return false }
        catalogRequest.cancel()
        // Publish the selected item's metadata before opening Now Playing.
        // Keep playback paused until the waiting screen has been presented.
        return playbackTransition.start(preparePlayback: { [weak self, weak controller] in
            guard let self, let controller, self.controller === controller else { return false }
            let model = MirrorModel.shared
            let presentation: MediaPlaybackPresentation = self.supportsVideo && !channel.isAudio ? .video : .audio
            model.returnToDisplay()
            let prepared = model.playMedia(channel, presentation: presentation,
                queue: MediaSeriesCatalog.playbackQueue(for: channel, in: channels), sourceID: sourceID, startPaused: true)
            CarPlayPlaybackTrace.record("list-prepared \(prepared)")
            if !prepared {
                self.showError(model.requiresMembership ? "Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir." : "Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
            }
            return prepared
        }, showWaiting: { [weak self, weak controller] completed in
            guard let self, let controller, self.controller === controller else { completed(false); return }
            if controller.topTemplate === CPNowPlayingTemplate.shared { completed(true); return }
            let presented: (Bool, Error?) -> Void = { [weak self] success, error in
                CarPlayPlaybackTrace.record("waiting-presented \(success)")
                if let error { self?.recordTemplateError(error) }
                completed(success)
            }
            if controller.templates.contains(where: { $0 === CPNowPlayingTemplate.shared }) {
                controller.pop(to: CPNowPlayingTemplate.shared, animated: true, completion: presented)
            } else {
                controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: presented)
            }
        }, playback: { [weak self, weak controller] in
            guard let self, let controller, self.controller === controller else { return }
            // CarPlay may already be changing the top template for video.
            // The successful presentation callback and selection token own ordering.
            MirrorModel.shared.playback.resume()
            CarPlayPlaybackTrace.record("list-resumed")
        })
    }

    /// Collapse episodes into series before presenting a category's contents.
    private func uniqueCatalogEntries(_ channels: [MediaChannel]) -> [MediaChannel] {
        let series = MediaSeriesCatalog(channels).series
        let seriesByChannel = Dictionary(series.flatMap { item in
            item.channels.map { ($0.id, item) }
        }, uniquingKeysWith: { first, _ in first })
        var seenSeries = Set<String>()
        return channels.filter { channel in
            guard let item = seriesByChannel[channel.id] else { return true }
            return seenSeries.insert(item.id).inserted
        }
    }

    private func showCatalog(_ channels: [MediaChannel], title: String, sourceID: UUID?,
                             offset: Int = 0, replacing: CPListTemplate? = nil) {
        let catalog = MediaSeriesCatalog(channels)
        guard !catalog.series.isEmpty else {
            showChannels(channels, title: title, sourceID: sourceID, offset: offset, replacing: replacing)
            return
        }
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        configureLibraryNavigation(template)
        if #available(iOS 26.0, *) {
            showArtworkCatalog(catalog, channels: channels, sourceID: sourceID,
                               replacing: replacing, template: template)
            return
        }
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        // Keep provider order, including standalone content in mixed categories.
        let seriesByChannel = Dictionary(catalog.series.flatMap { series in
            series.channels.map { ($0.id, series) }
        }, uniquingKeysWith: { first, _ in first })
        let entries = uniqueCatalogEntries(channels)
        var items = entries.dropFirst(offset).prefix(pageSize).map { channel in
            guard let series = seriesByChannel[channel.id] else {
                return channelItem(channel, channels: channels, sourceID: sourceID)
            }
            let detail = SeriesText.counts(series)
            let item = CPListItem(text: series.title, detailText: detail,
                                  image: UIImage(systemName: "rectangle.stack"))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.showSeriesSeasons(series, sourceID: sourceID)
                completion()
            }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showCatalog(channels, title: title, sourceID: sourceID,
                                  offset: max(0, offset - pageSize), replacing: template)
                completion()
            }
            items.insert(previous, at: 0)
        }
        if entries.count > offset + pageSize {
            let next = CPListItem(text: L10n.tr("Sonraki"), detailText: nil)
            next.handler = { [weak self, weak template] _, completion in
                self?.showCatalog(channels, title: title, sourceID: sourceID,
                                  offset: offset + pageSize, replacing: template)
                completion()
            }
            items.append(next)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { push(template) }
    }

    @available(iOS 26.0, *)
    private func showArtworkCatalog(_ catalog: MediaSeriesCatalog, channels: [MediaChannel],
                                    sourceID: UUID?, replacing: CPListTemplate?, template: CPListTemplate) {
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()
        let seriesByChannel = Dictionary(catalog.series.flatMap { series in
            series.channels.map { ($0.id, series) }
        }, uniquingKeysWith: { first, _ in first })
        let entries = uniqueCatalogEntries(channels)
        let orderedEntries = entries.enumerated().sorted { lhs, rhs in
            let left = seriesByChannel[lhs.element.id]?.title ?? lhs.element.title
            let right = seriesByChannel[rhs.element.id]?.title ?? rhs.element.title
            let order = left.localizedStandardCompare(right)
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }.map(\.element)
        let imagesPerRow = artworkCardsPerRow
        let posterEntries: [(channel: MediaChannel, series: MediaSeries?)] = orderedEntries.map { channel in
            (channel: channel, series: seriesByChannel[channel.id])
        }
        let posterRows = stride(from: 0, to: posterEntries.count, by: imagesPerRow).map { start -> (CPListImageRowItem, [(channel: MediaChannel, series: MediaSeries?)]) in
            let rowEntries = Array(posterEntries[start..<min(start + imagesPerRow, posterEntries.count)])
            let row = CPListImageRowItem(text: nil, cardElements: [], allowsMultipleLines: false)
            row.elements = rowEntries.map { entry in
                let series = entry.series
                let channel = series.map { $0.artworkChannel ?? $0.channels[0] } ?? entry.channel
                let image = channel.metadata.artworkURL.flatMap {
                    MediaArtworkStore.shared.cachedImage(at: $0, maximumPixelSize: 300)
                } ?? UIImage(systemName: "film") ?? UIImage()
                return CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                     title: series?.title ?? entry.channel.title,
                                                     subtitle: series.map { String(format: L10n.tr("%d sezon"), $0.seasons.count) }
                                                        ?? entry.channel.group,
                                                     tintColor: nil)
            }
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard let self, rowEntries.indices.contains(index) else { completion(); return }
                let entry = rowEntries[index]
                if let series = entry.series {
                    self.showSeriesSeasons(series, sourceID: sourceID)
                } else {
                    _ = self.play(entry.channel, channels: channels, sourceID: sourceID)
                }
                completion()
            }
            return (row, rowEntries)
        }
        let listItems: [any CPListTemplateItem] = posterRows.map(\.0)
        let countLabel = String(format: L10n.tr("%d içerik"), orderedEntries.count)
        template.updateSections([CPListSection(items: listItems, header: countLabel, sectionIndexTitle: nil)])
        if replacing == nil { push(template) }

        for (imageRow, rowEntries) in posterRows {
            let taskID = UUID()
            categoryArtworkTasks[taskID] = Task { @MainActor [weak self, weak imageRow] in
                guard let self, let imageRow else { return }
                var cards: [CPListImageRowItemCardElement] = []
                for entry in rowEntries {
                    guard !Task.isCancelled else { return }
                    let series = entry.series
                    let channel = series.map { $0.artworkChannel ?? $0.channels[0] } ?? entry.channel
                    let image: UIImage
                    if let artwork = channel.metadata.artworkURL,
                       let loaded = await MediaArtworkStore.shared.image(at: artwork, maximumPixelSize: 300) {
                        image = loaded
                    } else {
                        image = UIImage(systemName: entry.channel.isAudio ? "waveform" : "film") ?? UIImage()
                    }
                    cards.append(CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                               title: series?.title ?? entry.channel.title,
                                                               subtitle: series.map { String(format: L10n.tr("%d sezon"), $0.seasons.count) }
                                                                  ?? entry.channel.group,
                                                               tintColor: nil))
                }
                guard !Task.isCancelled else { return }
                imageRow.elements = cards
                self.categoryArtworkTasks.removeValue(forKey: taskID)
            }
        }
    }

    private func showSeriesSeasons(_ series: MediaSeries, sourceID: UUID?) {
        guard !series.seasons.isEmpty else {
            showChannels(series.channels, title: series.title, sourceID: sourceID)
            return
        }
        guard series.seasons.count > 1 else {
            let season = series.seasons[0]
            showChannels(season.channels, title: "\(series.title) · \(season.number). Sezon", sourceID: sourceID)
            return
        }

        let template = CPListTemplate(title: series.title, sections: [])
        configureLibraryNavigation(template)
        if #available(iOS 26.0, *) {
            showArtworkSeriesSeasons(series, sourceID: sourceID, template: template)
        } else {
            let items = series.seasons.map { season in
                let item = CPListItem(text: "\(season.number). Sezon",
                                      detailText: String(format: L10n.tr("%d bölüm"), season.channels.count),
                                      image: UIImage(systemName: "rectangle.stack"))
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, completion in
                    self?.showChannels(season.channels,
                                       title: "\(series.title) · \(season.number). Sezon",
                                       sourceID: sourceID)
                    completion()
                }
                return item
            }
            template.updateSections([CPListSection(items: items)])
            push(template)
        }
    }

    @available(iOS 26.0, *)
    private func showArtworkSeriesSeasons(_ series: MediaSeries, sourceID: UUID?, template: CPListTemplate) {
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()
        let poster = series.artworkChannel?.metadata.artworkURL.flatMap {
            MediaArtworkStore.shared.cachedImage(at: $0, maximumPixelSize: 600)
        } ?? UIImage(systemName: "film") ?? UIImage()
        let rows = stride(from: 0, to: series.seasons.count, by: artworkCardsPerRow).map { start -> (CPListImageRowItem, [MediaSeriesSeason]) in
            let seasons = Array(series.seasons[start..<min(start + artworkCardsPerRow, series.seasons.count)])
            let row = CPListImageRowItem(text: nil, cardElements: [], allowsMultipleLines: false)
            row.elements = seasons.map { season in
                CPListImageRowItemCardElement(image: poster, showsImageFullHeight: true,
                    title: "\(season.number). Sezon",
                    subtitle: String(format: L10n.tr("%d bölüm"), season.channels.count),
                    tintColor: nil)
            }
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard let self, seasons.indices.contains(index) else { completion(); return }
                let season = seasons[index]
                self.showChannels(season.channels,
                                  title: "\(series.title) · \(season.number). Sezon",
                                  sourceID: sourceID)
                completion()
            }
            return (row, seasons)
        }
        let countLabel = String(format: L10n.tr("%d sezon"), series.seasons.count)
        template.updateSections([CPListSection(items: rows.map(\.0), header: countLabel, sectionIndexTitle: nil)])
        push(template)

        guard let artwork = series.artworkChannel?.metadata.artworkURL else { return }
        for (row, seasons) in rows {
            let taskID = UUID()
            categoryArtworkTasks[taskID] = Task { @MainActor [weak self, weak row] in
                guard let self, let row else { return }
                let image = await MediaArtworkStore.shared.image(at: artwork, maximumPixelSize: 600)
                    ?? UIImage(systemName: "film") ?? UIImage()
                guard !Task.isCancelled else { return }
                row.elements = seasons.map { season in
                    CPListImageRowItemCardElement(image: image, showsImageFullHeight: true,
                        title: "\(season.number). Sezon",
                        subtitle: String(format: L10n.tr("%d bölüm"), season.channels.count),
                        tintColor: nil)
                }
                self.categoryArtworkTasks.removeValue(forKey: taskID)
            }
        }
    }

    private func channelItem(_ channel: MediaChannel, channels: [MediaChannel], sourceID: UUID?) -> CPListItem {
        let episode = channel.episode
        let title = episode.map { SeriesText.episode($0.number) } ?? channel.title
        let detail = episode?.resolvedTitle(providerTitle: channel.metadata.episodeTitle)
            ?? (episode == nil && !channel.group.isEmpty ? channel.group : nil)
        let item = CPListItem(text: title, detailText: detail,
                              image: UIImage(systemName: channel.isAudio ? "speaker.wave.2" : "play.circle"))
        if #available(iOS 26.4, *) {
            item.playbackConfiguration = CarPlayPlaybackTransition.selectionConfiguration()
        }
        item.handler = { [weak self, weak item] _, completion in
            guard let self else { completion(); return }
            let prepared = self.play(channel, channels: channels, sourceID: sourceID)
            if #available(iOS 26.4, *), prepared {
                item?.playbackConfiguration = CarPlayPlaybackTransition.configuration(for: channel, supportsVideo: self.supportsVideo)
            }
            completion()
        }
        return item
    }

    private func showChannels(_ channels: [MediaChannel], title: String, sourceID: UUID?,
                              offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        if #available(iOS 26.0, *), !channels.isEmpty {
            if channels.allSatisfy(\.isLive) {
                showArtworkChannelGrid(channels, sourceID: sourceID,
                                       countLabel: String(format: L10n.tr("%d kanal"), channels.count),
                                       fallbackSymbol: "tv", showsGroup: true,
                                       replacing: replacing, template: template)
                return
            }
            if channels.allSatisfy(\.isMovie) {
                showArtworkChannelGrid(channels, sourceID: sourceID,
                                       countLabel: String(format: L10n.tr("%d film"), channels.count),
                                       fallbackSymbol: "film", showsGroup: false,
                                       replacing: replacing, template: template)
                return
            }
        }
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        configureLibraryNavigation(template)
        let page = Array(channels.dropFirst(offset).prefix(pageSize))
        var items = page.map { channelItem($0, channels: channels, sourceID: sourceID) }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, sourceID: sourceID,
                                   offset: max(0, offset - pageSize), replacing: template)
                completion()
            }
            items.insert(previous, at: 0)
        }
        if channels.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Sonraki"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, sourceID: sourceID,
                                   offset: offset + pageSize, replacing: template)
                completion()
            }
            items.append(more)
        }
        let catalog = MediaSeriesCatalog(channels)
        if catalog.series.count == 1, catalog.ungrouped.isEmpty, let series = catalog.series.first {
            _ = series
            template.updateSections([CPListSection(items: items)])
        } else {
            template.updateSections([CPListSection(items: items)])
        }
        if replacing == nil { push(template) }
    }

    @available(iOS 26.0, *)
    private func showArtworkChannelGrid(_ channels: [MediaChannel], sourceID: UUID?,
                                       countLabel: String, fallbackSymbol: String, showsGroup: Bool,
                                       replacing: CPListTemplate?, template: CPListTemplate) {
        configureLibraryNavigation(template)
        categoryArtworkTasks.values.forEach { $0.cancel() }
        categoryArtworkTasks.removeAll()

        let rows = stride(from: 0, to: channels.count, by: artworkCardsPerRow).map { start -> (CPListImageRowItem, [MediaChannel]) in
            let rowChannels = Array(channels[start..<min(start + artworkCardsPerRow, channels.count)])
            let row = CPListImageRowItem(text: nil, cardElements: [], allowsMultipleLines: false)
            row.elements = rowChannels.map { channel in
                let image = channel.metadata.artworkURL.flatMap {
                    MediaArtworkStore.shared.cachedImage(at: $0, maximumPixelSize: 300)
                } ?? UIImage(systemName: fallbackSymbol) ?? UIImage()
                return CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                     title: channel.title,
                                                     subtitle: showsGroup ? channel.group : channel.metadata.year,
                                                     tintColor: nil)
            }
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard let self, rowChannels.indices.contains(index) else { completion(); return }
                _ = self.play(rowChannels[index], channels: channels, sourceID: sourceID)
                completion()
            }
            return (row, rowChannels)
        }

        template.updateSections([CPListSection(items: rows.map(\.0), header: countLabel, sectionIndexTitle: nil)])
        if replacing == nil { push(template) }

        for (row, rowChannels) in rows {
            let taskID = UUID()
            categoryArtworkTasks[taskID] = Task { @MainActor [weak self, weak row] in
                guard let self, let row else { return }
                var cards: [CPListImageRowItemCardElement] = []
                for channel in rowChannels {
                    guard !Task.isCancelled else { return }
                    let image: UIImage
                    if let artwork = channel.metadata.artworkURL,
                       let loaded = await MediaArtworkStore.shared.image(at: artwork, maximumPixelSize: 300) {
                        image = loaded
                    } else {
                        image = UIImage(systemName: fallbackSymbol) ?? UIImage()
                    }
                    guard !Task.isCancelled else { return }
                    cards.append(CPListImageRowItemCardElement(image: image, showsImageFullHeight: false,
                                                               title: channel.title,
                                                               subtitle: showsGroup ? channel.group : channel.metadata.year,
                                                               tintColor: nil))
                }
                guard !Task.isCancelled else { return }
                row.elements = cards
                self.categoryArtworkTasks.removeValue(forKey: taskID)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [L10n.tr(message)],
            actions: [CPAlertAction(title: L10n.tr("Tamam"), style: .default) { [weak self] _ in
                self?.controller?.dismissTemplate(animated: true) { [weak self] _, error in
                    if let error { self?.recordTemplateError(error) }
                }
            }])
        controller?.presentTemplate(alert, animated: true) { [weak self] _, error in
            if let error { self?.recordTemplateError(error) }
        }
    }
}

/// Prepare the selection before opening Now Playing. Resume on the next
/// actor turn so CarPlay has received the list handler's completion.
@MainActor
final class CarPlayPlaybackTransition {
    private var generation = UUID()

    /// With the Audio entitlement, requesting video before the handler can
    /// prevent selection delivery. Publish video only after preparing playback.
    @available(iOS 26.4, *)
    static func selectionConfiguration() -> CPPlaybackConfiguration {
        CPPlaybackConfiguration(preferredPresentation: .audio,
            playbackAction: .play, elapsedTime: .zero, duration: .zero)
    }

    static func resetSelections(in template: CPListTemplate) {
        guard #available(iOS 26.4, *) else { return }
        for section in template.sections {
            for case let item as CPListItem in section.items where item.playbackConfiguration?.preferredPresentation == .video {
                item.playbackConfiguration = selectionConfiguration()
            }
        }
    }

    @available(iOS 26.4, *)
    static func configuration(for channel: MediaChannel, supportsVideo: Bool) -> CPPlaybackConfiguration {
        CPPlaybackConfiguration(preferredPresentation: supportsVideo && !channel.isAudio ? .video : .audio,
            playbackAction: .play, elapsedTime: .zero, duration: .zero)
    }

    func cancel() { generation = UUID() }

    @discardableResult
    func start(preparePlayback: () -> Bool, showWaiting: (@escaping (Bool) -> Void) -> Void,
               playback: @escaping () -> Void) -> Bool {
        cancel()
        let selection = generation
        guard preparePlayback(), generation == selection else { return false }
        showWaiting { [weak self] ready in
            guard let self, self.generation == selection else { return }
            guard ready else { self.cancel(); return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == selection else { return }
                self.cancel()
                playback()
            }
        }
        return generation == selection
    }
}

/// A cached catalog opens immediately. Refreshing it must not push a second
/// template or reset the page the driver has already selected.
@MainActor
final class CarPlayCatalogRequest {
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var completion: (() -> Void)?

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        finish()
    }

    func start(load: @escaping (@escaping @MainActor ([MediaChannel]) -> Void) async throws -> [MediaChannel],
               show: @escaping ([MediaChannel]) -> Void, failure: @escaping () -> Void,
               completion: @escaping () -> Void) {
        cancel()
        self.completion = completion
        let token = generation
        task = Task { [weak self] in
            var displayed = false
            let display: @MainActor ([MediaChannel]) -> Void = { [weak self] channels in
                guard let self, self.generation == token, !displayed else { return }
                displayed = true
                show(channels)
                guard self.generation == token else { return }
                self.finish()
            }
            do { display(try await load(display)) }
            catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if !displayed { failure() }
            }
            guard let self, self.generation == token else { return }
            self.task = nil
            self.finish()
        }
    }

    private func finish() {
        let callback = completion
        completion = nil
        callback?()
    }
}

@MainActor
enum CarPlayFavoritesMenu {
    /// Keep navigation items out of the playable list and preserve each favorite's source.
    @discardableResult
    static func update(_ template: CPListTemplate, entries: [FavoriteMedia], sourceNames: [UUID: String] = [:],
                       offset: Int = 0, supportsVideo: Bool,
                       open: @escaping (FavoriteMedia, @escaping (Bool) -> Void) -> Void,
                       page: @escaping (Int) -> Void) -> Int {
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        let lastPage = max(0, entries.count - 1) / pageSize * pageSize
        let start = min(max(0, offset) / pageSize * pageSize, lastPage)
        var items = entries.dropFirst(start).prefix(pageSize).map { favorite in
            let kind = favorite.series != nil ? "Dizi" : favorite.channel.episode != nil ? "Bölüm"
                : favorite.channel.isLive ? "Canlı yayın" : favorite.channel.isAudio ? "Ses" : "Video"
            let details = [L10n.tr(kind), favorite.sourceID.flatMap { sourceNames[$0] }].compactMap { $0 }.joined(separator: " · ")
            let item = CPListItem(text: favorite.title, detailText: details,
                                 image: UIImage(systemName: favorite.series != nil ? "rectangle.stack" : "heart.fill"))
            if #available(iOS 26.4, *), favorite.series == nil {
                item.playbackConfiguration = CarPlayPlaybackTransition.selectionConfiguration()
            }
            item.handler = { [weak item] _, completion in
                open(favorite) { prepared in
                    if #available(iOS 26.4, *), favorite.series == nil, prepared {
                        item?.playbackConfiguration = CarPlayPlaybackTransition.configuration(for: favorite.channel, supportsVideo: supportsVideo)
                    }
                    completion()
                }
            }
            return item
        }
        if start > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { _, completion in page(start - pageSize); completion() }
            items.insert(previous, at: 0)
        }
        if entries.count > start + pageSize {
            let next = CPListItem(text: L10n.tr("Sonraki"), detailText: nil)
            next.handler = { _, completion in page(start + pageSize); completion() }
            items.append(next)
        }
        template.emptyViewTitleVariants = [L10n.tr("Favoriler")]
        template.emptyViewSubtitleVariants = [L10n.tr("Sevdiğin içerikleri kalp düğmesiyle buraya ekle.")]
        template.updateSections(items.isEmpty ? [] : [CPListSection(items: items)])
        return start
    }
}
