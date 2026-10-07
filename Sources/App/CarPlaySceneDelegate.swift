import CarPlay
import Combine

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
    private var controller: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private var list: CPListTemplate?
    private var timer: Timer?
    private var lastSignature = ""
    private var loading: Task<Void, Never>?
    private let capabilities = CarPlayCapabilities.current

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.connected(sessionID: scene.session.persistentIdentifier)
        controller = interfaceController
        configuration = CPSessionConfiguration(delegate: self)
        let supported: Bool?
        if capabilities.video, #available(iOS 26.4, *) { supported = configuration?.supportsVideoPlayback }
        else { supported = nil }
        MirrorModel.shared.connected(supportsVideo: supported)
        let list = CPListTemplate(title: BrandIdentity.name, sections: [])
        self.list = list
        render()
        interfaceController.setRootTemplate(list, animated: false) { _, error in
            if let error { Task { @MainActor in MirrorModel.shared.errorMessage = error.localizedDescription } }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CarConnectionReminderStore.shared.disconnected(sessionID: scene.session.persistentIdentifier)
        loading?.cancel(); loading = nil
        timer?.invalidate()
        timer = nil
        controller = nil
        configuration = nil
        list = nil
        lastSignature = ""
        MirrorModel.shared.disconnected()
    }

    private func render() {
        let model = MirrorModel.shared
        let signature = "\(model.readyToPlay)-\(model.captureTitle)-\(model.supportsVideo == true)-\(model.probeStartedAt != nil)-\(model.mediaTitle ?? "")-\(SourceLibrary.shared.sources.map(\.id))-\(L10n.language)"
        guard signature != lastSignature else { return }
        lastSignature = signature

        var items: [CPListItem] = []
        if capabilities.video {
            let mirror = CPListItem(text: L10n.tr("iPhone ekranı"), detailText: model.captureTitle,
                                    image: UIImage(systemName: "iphone.radiowaves.left.and.right"))
            mirror.isEnabled = model.readyToPlay && model.supportsVideo == true
            if #available(iOS 26.4, *) {
                mirror.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            mirror.handler = { _, completion in
                model.playInCar()
                completion()
            }
            items.append(mirror)
        }
        let sources = CPListItem(text: L10n.tr("Kaynaklar"), detailText: nil, image: UIImage(systemName: "play.rectangle.on.rectangle"))
        sources.isEnabled = capabilities.audio && !SourceLibrary.shared.sources.isEmpty
        sources.handler = { [weak self] _, completion in self?.showSources(); completion() }
        items.append(sources)
        if model.mediaTitle != nil {
            let playing = CPListItem(text: L10n.tr("Şu An Çalıyor"), detailText: model.mediaTitle,
                                     image: UIImage(systemName: "waveform"))
            playing.handler = { [weak self] _, completion in self?.showNowPlaying(); completion() }
            items.append(playing)
        }
        let stop = CPListItem(text: L10n.tr(model.mediaTitle == nil ? "Paylaşımı durdur" : "Oynatmayı durdur"), detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting || model.probeStartedAt != nil || model.mediaTitle != nil
        stop.handler = { _, completion in model.stopBroadcast(); model.stopProbe(); completion() }
        if stop.isEnabled || capabilities.video { items.append(stop) }
        #if DEBUG
        if capabilities.video {
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
                        let alert = CPAlertTemplate(titleVariants: [L10n.tr("Kaynak yüklenemedi. Adresi ve bağlantını kontrol et.")],
                            actions: [CPAlertAction(title: L10n.tr("Tamam"), style: .default) { [weak self] _ in
                                self?.controller?.dismissTemplate(animated: true, completion: nil)
                            }])
                        self?.controller?.presentTemplate(alert, animated: true, completion: nil)
                    }
                }
            }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showSources(offset: max(0, offset - pageSize), replacing: template); completion()
            }
            items.insert(previous, at: 0)
        }
        if sources.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Diğer kaynaklar"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showSources(offset: offset + pageSize, replacing: template); completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { controller?.pushTemplate(template, animated: true, completion: nil) }
    }

    private func showChannels(_ channels: [MediaChannel], title: String, sourceID: UUID, offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = channels.dropFirst(offset).prefix(pageSize).map { channel in
            let item = CPListItem(text: channel.title, detailText: channel.group.isEmpty ? nil : channel.group)
            let video = capabilities.canPresentVideo(vehicleSupportsVideo: MirrorModel.shared.supportsVideo)
            if #available(iOS 26.4, *) {
                item.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: video ? .video : .audio,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            item.handler = { [weak self] _, completion in
                let started = MirrorModel.shared.playMedia(channel, presentation: video ? .video : .audio, sourceID: sourceID)
                completion()
                if started {
                    // iOS 26.4+ presents the preferred playback UI through CPPlaybackConfiguration.
                    if #unavailable(iOS 26.4) { self?.showNowPlaying() }
                } else { self?.showPlaybackError() }
            }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, sourceID: sourceID, offset: max(0, offset - pageSize), replacing: template); completion()
            }
            items.insert(previous, at: 0)
        }
        if channels.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Diğer kanallar"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, sourceID: sourceID, offset: offset + pageSize, replacing: template); completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { controller?.pushTemplate(template, animated: true, completion: nil) }
    }

    private func showNowPlaying() {
        guard capabilities.audio, let controller, MirrorModel.shared.mediaTitle != nil else { return }
        let template = CPNowPlayingTemplate.shared
        guard controller.topTemplate !== template else { return }
        controller.pushTemplate(template, animated: true, completion: nil)
    }

    private func showPlaybackError() {
        let alert = CPAlertTemplate(titleVariants: [L10n.tr("Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")],
            actions: [CPAlertAction(title: L10n.tr("Tamam"), style: .default) { [weak self] _ in
                self?.controller?.dismissTemplate(animated: true, completion: nil)
            }])
        controller?.presentTemplate(alert, animated: true, completion: nil)
    }
}
