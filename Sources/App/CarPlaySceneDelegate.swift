import CarPlay
import UIKit
import Combine

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
    private var controller: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private var list: CPListTemplate?
    private var menuUpdates: AnyCancellable?
    private let catalogRequest = CarPlayCatalogRequest()
    private let playbackTransition = CarPlayPlaybackTransition()
    private var loading: Task<Void, Never>?
    private weak var favoritesList: CPListTemplate?
    private var favoritesOffset = 0
    private let libraryTemplates = NSHashTable<CPListTemplate>.weakObjects()

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.connected(sessionID: scene.session.persistentIdentifier)
        controller = interfaceController
        configuration = CPSessionConfiguration(delegate: self)
        let home = CPListTemplate(title: BrandIdentity.name, sections: [])
        list = home
        let sources = SourceLibrary.shared.sources
        let root = sources.isEmpty ? home : CPListTemplate(title: nil, sections: [])
        if root !== home { configureLibraryNavigation(root) }
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
        menuUpdates = Self.menuChanges(model: .shared, library: .shared, favorites: .shared)
            .debounce(for: .milliseconds(20), scheduler: RunLoop.main)
            .sink { [weak self] in self?.render() }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.disconnected(sessionID: scene.session.persistentIdentifier)
        menuUpdates = nil
        catalogRequest.cancel()
        playbackTransition.cancel()
        list = nil
        favoritesList = nil
        favoritesOffset = 0
        libraryTemplates.removeAllObjects()
        MirrorModel.shared.disconnected()
        loading?.cancel()
        loading = nil
        controller = nil
        configuration = nil
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
        if let list { updateNavigationButtons(list) }
        if let favoritesList { showFavorites(offset: favoritesOffset, replacing: favoritesList) }
        controller?.templates.compactMap { $0 as? CPListTemplate }.forEach(updateNavigationButtons)
    }

    private var supportsVideo: Bool {
        if #available(iOS 26.4, *) { return configuration?.supportsVideoPlayback == true }
        return false
    }

    /// Observe menu inputs, not playback ticks or capture statistics. Delivery is
    /// deferred so @Published's willSet notifications never render the old value.
    static func menuChanges(model: MirrorModel, library: SourceLibrary, favorites: MediaFavorites) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            model.$sessionState.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$capture.map { $0?.canPlay() == true }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$supportsVideo.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$probeStartedAt.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$mediaTitle.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$requiresMembership.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            library.$sources.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            favorites.$entries.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in L10n.language }.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]).eraseToAnyPublisher()
    }

    private func push(_ template: CPTemplate) {
        if let template = template as? CPListTemplate { updateNavigationButtons(template) }
        controller?.pushTemplate(template, animated: true) { [weak self] _, error in
            if let error { self?.recordTemplateError(error) }
        }
    }

    private func updateNavigationButtons(_ template: CPListTemplate) {
        var buttons: [CPBarButton] = []
        if MirrorModel.shared.mediaTitle != nil, let stopImage = UIImage(systemName: "stop.fill") {
            let stop = CPBarButton(image: stopImage) { _ in
                MirrorModel.shared.stopPlayback(hideSavedPlaybackBar: true)
            }
            buttons.append(stop)
        }
        if libraryTemplates.contains(template), let image = UIImage(systemName: "house") {
            let home = CPBarButton(image: image) { [weak self] _ in
                self?.showHome()
            }
            // CarPlay lays out trailing buttons from the trailing edge inward.
            // Keep Home first visually, with Stop next to the system MiniPlayer.
            buttons.append(home)
        }
        template.trailingNavigationBarButtons = buttons
    }

    private func configureLibraryNavigation(_ template: CPListTemplate) {
        libraryTemplates.add(template)
        template.leadingNavigationBarButtons = [
            CPBarButton(title: L10n.tr("Favoriler")) { [weak self] _ in self?.showFavorites() }
        ]
        updateNavigationButtons(template)
    }

    private func showHome() {
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
        var values = DiagnosticValues()
        values.screen = .carPlay
        values.failure = DiagnosticFailure(error)
        MirrorModel.shared.record(.failure, values: values)
    }

    private func showLibraryRoot(_ template: CPListTemplate) {
        // Sources/categories are destinations, rather than another step above
        // Home. Making them the root removes CarPlay's automatic Back button.
        controller?.setRootTemplate(template, animated: true) { [weak self] _, error in
            if let error { self?.recordTemplateError(error) }
        }
    }

    private func showSources(offset: Int = 0, replacing: CPListTemplate? = nil) {
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
        loading?.cancel()
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
        configureLibraryNavigation(template)
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = categories.dropFirst(offset).prefix(pageSize).map { category in
            let name = category.name.isEmpty ? L10n.tr("Diğer kanallar") : category.name
            let item = CPListItem(text: name,
                                  detailText: String(format: L10n.tr("%d içerik"), category.channels.count),
                                  image: UIImage(systemName: "folder"))
            item.handler = { [weak self] _, completion in
                self?.showChannels(category.channels, title: name, sourceID: sourceID)
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

    private func showFavorites(offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: L10n.tr("Favoriler"), sections: [])
        favoritesList = template
        favoritesOffset = CarPlayFavoritesMenu.update(template, entries: MediaFavorites.shared.entries,
            sourceNames: Dictionary(uniqueKeysWithValues: SourceLibrary.shared.sources.map { ($0.id, $0.name) }),
            offset: offset, supportsVideo: supportsVideo,
            open: { [weak self] item, completion in
                guard let self else { completion(); return }
                self.openFavorite(item, completion: completion)
            }, page: { [weak self, weak template] page in
                guard let template else { return }
                self?.showFavorites(offset: page, replacing: template)
            })
        if replacing == nil { push(template) }
    }

    private func openFavorite(_ favorite: FavoriteMedia, completion: @escaping () -> Void) {
        catalogRequest.cancel()
        loading?.cancel()
        loading = Task { [weak self] in
            defer { completion() }
            guard let self else { return }
            let model = MirrorModel.shared
            do {
                let channels: [MediaChannel]
                if let sourceID = favorite.sourceID,
                   let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) {
                    if favorite.series != nil {
                        channels = try await SourceLibrary.shared.channels(for: source)
                    } else {
                        channels = SourceLibrary.shared.cachedChannels(for: source)
                            ?? favorite.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID)
                    }
                } else {
                    // Individual favorites retain their playable URL, just as
                    // on iPhone. A whole series still needs its current source.
                    guard favorite.series == nil || favorite.sourceID == nil else {
                        self.showError("İçerik bulunamadı"); return
                    }
                    channels = favorite.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID)
                }
                guard !Task.isCancelled else { return }
                if favorite.series != nil {
                    guard let series = favorite.resolveSeries(in: channels) else {
                        self.showError("İçerik bulunamadı"); return
                    }
                    self.showChannels(series.channels, title: series.title, sourceID: favorite.sourceID)
                } else {
                    self.play(favorite.channel, channels: channels, sourceID: favorite.sourceID)
                }
            } catch {
                if !Task.isCancelled { self.showError("İçerikler yüklenemedi.") }
            }
        }
    }

    private func play(_ channel: MediaChannel, channels: [MediaChannel], sourceID: UUID?) {
        guard let controller else { return }
        // Publish the selected item's metadata before opening Now Playing.
        // Keep playback paused until the waiting screen has been presented.
        playbackTransition.start(preparePlayback: { [weak self, weak controller] in
            guard let self, let controller, self.controller === controller else { return false }
            let model = MirrorModel.shared
            let presentation: MediaPlaybackPresentation = self.supportsVideo && !channel.isAudio ? .video : .audio
            model.returnToDisplay()
            let prepared = model.playMedia(channel, presentation: presentation,
                queue: MediaSeriesCatalog.playbackQueue(for: channel, in: channels), sourceID: sourceID, startPaused: true)
            if !prepared {
                self.showError(model.requiresMembership ? "Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir." : "Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
            }
            return prepared
        }, showWaiting: { [weak self, weak controller] completed in
            guard let self, let controller, self.controller === controller else { completed(false); return }
            if controller.topTemplate === CPNowPlayingTemplate.shared { completed(true); return }
            let presented: (Bool, Error?) -> Void = { [weak self] success, error in
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
        })
    }

    private func showChannels(_ channels: [MediaChannel], title: String, sourceID: UUID?,
                              offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = channels.dropFirst(offset).prefix(pageSize).map { channel in
            let item = CPListItem(text: channel.title, detailText: channel.group.isEmpty ? nil : channel.group)
            if #available(iOS 26.4, *) {
                item.playbackConfiguration = CarPlayPlaybackTransition.configuration(for: channel, supportsVideo: supportsVideo)
            }
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                self.play(channel, channels: channels, sourceID: sourceID)
                completion()
            }
            return item
        }
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
            let more = CPListItem(text: L10n.tr("Diğer kanallar"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, sourceID: sourceID,
                                   offset: offset + pageSize, replacing: template)
                completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { push(template) }
    }

    private func showNowPlaying() {
        guard let controller, MirrorModel.shared.mediaTitle != nil,
              controller.topTemplate !== CPNowPlayingTemplate.shared else { return }
        push(CPNowPlayingTemplate.shared)
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

/// Prepare paused media before Now Playing, then resume on the next actor turn
/// so the selection handler finishes before CarPlay automatically presents video.
@MainActor
final class CarPlayPlaybackTransition {
    private var generation = UUID()

    @available(iOS 26.4, *)
    static func configuration(for channel: MediaChannel, supportsVideo: Bool) -> CPPlaybackConfiguration {
        CPPlaybackConfiguration(preferredPresentation: supportsVideo && !channel.isAudio ? .video : .audio,
            playbackAction: .play, elapsedTime: .zero, duration: .zero)
    }

    func cancel() { generation = UUID() }

    func start(preparePlayback: () -> Bool, showWaiting: (@escaping (Bool) -> Void) -> Void,
               playback: @escaping () -> Void) {
        cancel()
        let selection = generation
        guard preparePlayback(), generation == selection else { return }
        showWaiting { [weak self] ready in
            guard let self, self.generation == selection else { return }
            guard ready else { self.cancel(); return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == selection else { return }
                self.cancel()
                playback()
            }
        }
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
                self.finish()
            }
            do { display(try await load(display)) }
            catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if !displayed { failure() }
            }
            guard let self, self.generation == token else { return }
            self.finish()
            self.task = nil
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
                       open: @escaping (FavoriteMedia, @escaping () -> Void) -> Void,
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
                item.playbackConfiguration = CarPlayPlaybackTransition.configuration(for: favorite.channel, supportsVideo: supportsVideo)
            }
            item.handler = { _, completion in open(favorite, completion) }
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
