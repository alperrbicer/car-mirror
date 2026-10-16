import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
    private var controller: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private var list: CPListTemplate?
    private var timer: Timer?
    private var lastSignature = ""
    private var loading: Task<Void, Never>?
    private weak var favoritesList: CPListTemplate?
    private var favoritesOffset = 0

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.connected(sessionID: scene.session.persistentIdentifier)
        controller = interfaceController
        configuration = CPSessionConfiguration(delegate: self)
        let root = CPListTemplate(title: BrandIdentity.name, sections: [])
        list = root
        MirrorModel.shared.connected(supportsVideo: supportsVideo)
        render()
        interfaceController.setRootTemplate(root, animated: false) { success, error in
            Task { @MainActor in
                let model = MirrorModel.shared
                if success { model.record(.carTemplateReady) }
                else if let error {
                    var values = DiagnosticValues()
                    values.screen = .carPlay
                    values.failure = DiagnosticFailure(error)
                    model.record(.failure, values: values)
                    model.errorMessage = error.localizedDescription
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.disconnected(sessionID: scene.session.persistentIdentifier)
        timer?.invalidate()
        timer = nil
        list = nil
        favoritesList = nil
        favoritesOffset = 0
        lastSignature = ""
        MirrorModel.shared.disconnected()
        loading?.cancel()
        loading = nil
        controller = nil
        configuration = nil
    }

    private func render() {
        let model = MirrorModel.shared
        let signature = "\(model.readyToPlay)-\(model.captureTitle)-\(model.supportsVideo == true)-\(model.probeStartedAt != nil)-\(model.mediaTitle ?? "")-\(model.requiresMembership)-\(SourceLibrary.shared.sources.map(\.id))-\(MediaFavorites.shared.entries.map(\.id))-\(L10n.language)"
        guard signature != lastSignature else { return }
        lastSignature = signature

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
                mirror.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video,
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
        sources.handler = { [weak self] _, completion in self?.showSources(); completion() }
        items.append(sources)
        let favorites = CPListItem(text: L10n.tr("Favoriler"),
                                   detailText: String(format: L10n.tr("%d içerik"), MediaFavorites.shared.entries.count),
                                   image: UIImage(systemName: "heart.fill"))
        favorites.handler = { [weak self] _, completion in self?.showFavorites(); completion() }
        items.append(favorites)
        if model.mediaTitle != nil {
            let playing = CPListItem(text: L10n.tr("Şu An Çalıyor"), detailText: model.mediaTitle,
                                     image: UIImage(systemName: "waveform"))
            playing.handler = { [weak self] _, completion in self?.showNowPlaying(); completion() }
            items.append(playing)
        }
        let stop = CPListItem(text: L10n.tr(model.mediaTitle == nil ? "Paylaşımı durdur" : "Oynatmayı durdur"), detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting || model.probeStartedAt != nil || model.mediaTitle != nil
        stop.handler = { _, completion in model.stopBroadcast(hideSavedPlaybackBar: true); model.stopProbe(); model.stopPlayback(); completion() }
        if stop.isEnabled || supportsVideo { items.append(stop) }
        #if DEBUG
        if supportsVideo {
            let probe = CPListItem(text: L10n.tr("Ekran bağlantı testi"), detailText: nil, image: UIImage(systemName: "display"))
            probe.isEnabled = model.supportsVideo == true && !model.broadcasting
            if #available(iOS 26.4, *) {
                probe.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            probe.handler = { _, completion in model.startVideoProbe(); completion() }
            items.append(probe)
        }
        #endif
        list?.updateSections([CPListSection(items: items)])
        if let favoritesList { showFavorites(offset: favoritesOffset, replacing: favoritesList) }
    }

    private var supportsVideo: Bool {
        if #available(iOS 26.4, *) { return configuration?.supportsVideoPlayback == true }
        return false
    }

    private func showSources(offset: Int = 0, replacing: CPListTemplate? = nil) {
        let sources = SourceLibrary.shared.sources
        let template = replacing ?? CPListTemplate(title: L10n.tr("Kaynaklar"), sections: [])
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = sources.dropFirst(offset).prefix(pageSize).map { source in
            let item = CPListItem(text: source.name, detailText: nil)
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                self.loading?.cancel()
                self.loading = Task { [weak self] in
                    defer { completion() }
                    do {
                        let channels = try await SourceLibrary.shared.channels(for: source)
                        guard !Task.isCancelled else { return }
                        self?.showChannels(channels, title: source.name, sourceID: source.id)
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.showError("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.")
                    }
                }
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
        if replacing == nil { controller?.pushTemplate(template, animated: true) }
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
        if replacing == nil { controller?.pushTemplate(template, animated: true) }
    }

    private func openFavorite(_ favorite: FavoriteMedia, completion: @escaping () -> Void) {
        loading?.cancel()
        loading = Task { [weak self] in
            defer { completion() }
            guard let self else { return }
            let model = MirrorModel.shared
            do {
                let channels: [MediaChannel]
                if let sourceID = favorite.sourceID {
                    guard let source = SourceLibrary.shared.sources.first(where: { $0.id == sourceID }) else {
                        self.showError("İçerik bulunamadı"); return
                    }
                    if favorite.series != nil {
                        channels = try await SourceLibrary.shared.channels(for: source)
                    } else {
                        channels = SourceLibrary.shared.cachedChannels(for: source)
                            ?? favorite.fallbackCatalog(currentChannels: model.playbackQueue, sourceID: model.playbackSourceID)
                    }
                } else {
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
        let model = MirrorModel.shared
        let presentation: MediaPlaybackPresentation = supportsVideo && !channel.isAudio ? .video : .audio
        model.returnToDisplay()
        let started = model.playMedia(channel, presentation: presentation,
            queue: MediaSeriesCatalog.playbackQueue(for: channel, in: channels), sourceID: sourceID)
        if started, #unavailable(iOS 26.4) { showNowPlaying() }
        if !started {
            showError(model.requiresMembership ? "Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir." : "Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
        }
    }

    private func showChannels(_ channels: [MediaChannel], title: String, sourceID: UUID?,
                              offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = channels.dropFirst(offset).prefix(pageSize).map { channel in
            let item = CPListItem(text: channel.title, detailText: channel.group.isEmpty ? nil : channel.group)
            if #available(iOS 26.4, *) {
                item.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: supportsVideo && !channel.isAudio ? .video : .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
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
        if replacing == nil { controller?.pushTemplate(template, animated: true) }
    }

    private func showNowPlaying() {
        guard let controller, MirrorModel.shared.mediaTitle != nil,
              controller.topTemplate !== CPNowPlayingTemplate.shared else { return }
        controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
    }

    private func showError(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [L10n.tr(message)],
            actions: [CPAlertAction(title: L10n.tr("Tamam"), style: .default) { [weak self] _ in
                self?.controller?.dismissTemplate(animated: true)
            }])
        controller?.presentTemplate(alert, animated: true)
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
                item.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: supportsVideo && !favorite.channel.isAudio ? .video : .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
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
