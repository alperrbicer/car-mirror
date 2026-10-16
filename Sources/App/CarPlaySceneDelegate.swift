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
        lastSignature = ""
        MirrorModel.shared.disconnected()
        loading?.cancel()
        loading = nil
        controller = nil
        configuration = nil
    }

    private func render() {
        let model = MirrorModel.shared
        let signature = "\(model.readyToPlay)-\(model.captureTitle)-\(model.supportsVideo == true)-\(model.probeStartedAt != nil)-\(model.mediaTitle ?? "")-\(model.requiresMembership)-\(SourceLibrary.shared.sources.map(\.id))-\(L10n.language)"
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
        if model.mediaTitle != nil {
            let playing = CPListItem(text: L10n.tr("Şu An Çalıyor"), detailText: model.mediaTitle,
                                     image: UIImage(systemName: "waveform"))
            playing.handler = { [weak self] _, completion in self?.showNowPlaying(); completion() }
            items.append(playing)
        }
        let stop = CPListItem(text: L10n.tr(model.mediaTitle == nil ? "Paylaşımı durdur" : "Oynatmayı durdur"), detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting || model.probeStartedAt != nil || model.mediaTitle != nil
        stop.handler = { _, completion in model.stopBroadcast(); model.stopProbe(); model.stopPlayback(); completion() }
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

    private func showChannels(_ channels: [MediaChannel], title: String, sourceID: UUID,
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
                let presentation: MediaPlaybackPresentation = self.supportsVideo && !channel.isAudio ? .video : .audio
                let started = MirrorModel.shared.playMedia(channel, presentation: presentation, sourceID: sourceID)
                completion()
                if started, #unavailable(iOS 26.4) { self.showNowPlaying() }
                if !started {
                    self.showError(MirrorModel.shared.requiresMembership ? "Oynatmak ve paylaşmak için Mirivo Pro’yu etkinleştir." : "Yayın başlatılamadı. Kaynağı kontrol edip yeniden dene.")
                }
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
