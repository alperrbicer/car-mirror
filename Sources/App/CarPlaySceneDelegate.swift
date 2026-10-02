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

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        configuration = CPSessionConfiguration(delegate: self)
        let supported: Bool?
        if #available(iOS 26.4, *) { supported = configuration?.supportsVideoPlayback }
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
        let stop = CPListItem(text: L10n.tr(model.mediaTitle == nil ? "Paylaşımı durdur" : "Oynatmayı durdur"), detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting || model.probeStartedAt != nil || model.mediaTitle != nil
        stop.handler = { _, completion in model.stopBroadcast(); model.stopProbe(); completion() }
        var items = [mirror, stop]
        #if DEBUG
        let probe = CPListItem(text: L10n.tr("Ekran bağlantı testi"), detailText: nil, image: UIImage(systemName: "display"))
        probe.isEnabled = model.supportsVideo == true && !model.broadcasting
        if #available(iOS 26.4, *) {
            probe.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video,
                playbackAction: .play, elapsedTime: .zero, duration: .zero)
        }
        probe.handler = { _, completion in model.startVideoProbe(); completion() }
        items.append(probe)
        #endif
        let sources = CPListItem(text: L10n.tr("Kaynaklar"), detailText: nil, image: UIImage(systemName: "play.rectangle.on.rectangle"))
        sources.isEnabled = !SourceLibrary.shared.sources.isEmpty && model.supportsVideo == true
        sources.handler = { [weak self] _, completion in self?.showSources(); completion() }
        items.append(sources)
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
                        self?.showChannels(channels, title: source.name)
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

    private func showChannels(_ channels: [MediaChannel], title: String, offset: Int = 0, replacing: CPListTemplate? = nil) {
        let template = replacing ?? CPListTemplate(title: title, sections: [])
        let pageSize = max(1, min(90, CPListTemplate.maximumItemCount - 2))
        var items = channels.dropFirst(offset).prefix(pageSize).map { channel in
            let item = CPListItem(text: channel.title, detailText: channel.group.isEmpty ? nil : channel.group)
            if #available(iOS 26.4, *) {
                item.playbackConfiguration = CPPlaybackConfiguration(preferredPresentation: .video,
                    playbackAction: .play, elapsedTime: .zero, duration: .zero)
            }
            item.handler = { _, completion in MirrorModel.shared.playMedia(channel); completion() }
            return item
        }
        if offset > 0 {
            let previous = CPListItem(text: L10n.tr("Önceki sayfa"), detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, offset: max(0, offset - pageSize), replacing: template); completion()
            }
            items.insert(previous, at: 0)
        }
        if channels.count > offset + pageSize {
            let more = CPListItem(text: L10n.tr("Diğer kanallar"), detailText: nil)
            more.handler = { [weak self, weak template] _, completion in
                self?.showChannels(channels, title: title, offset: offset + pageSize, replacing: template); completion()
            }
            items.append(more)
        }
        template.updateSections([CPListSection(items: items)])
        if replacing == nil { controller?.pushTemplate(template, animated: true, completion: nil) }
    }

}
