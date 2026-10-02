import CarPlay
import Combine

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
    private var controller: CPInterfaceController?
    private var configuration: CPSessionConfiguration?
    private var list: CPListTemplate?
    private var timer: Timer?
    private var lastSignature = ""

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        configuration = CPSessionConfiguration(delegate: self)
        let supported: Bool?
        if #available(iOS 26.4, *) { supported = configuration?.supportsVideoPlayback }
        else { supported = nil }
        MirrorModel.shared.connected(supportsVideo: supported)
        let list = CPListTemplate(title: "CarMirror", sections: [])
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
        let signature = "\(model.readyToPlay)-\(model.captureTitle)-\(model.supportsVideo == true)"
        guard signature != lastSignature else { return }
        lastSignature = signature

        let mirror = CPListItem(text: "iPhone ekranı", detailText: model.captureTitle,
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
        let instruction = CPListItem(text: "Ekran paylaşımını iPhone’dan başlat",
            detailText: "Ardından YouTube veya IPTV uygulamanı aç.")
        instruction.isEnabled = false
        let stop = CPListItem(text: "Paylaşımı durdur", detailText: nil, image: UIImage(systemName: "stop.circle"))
        stop.isEnabled = model.broadcasting
        stop.handler = { _, completion in model.stopBroadcast(); completion() }
        list?.updateSections([CPListSection(items: [mirror, instruction, stop])])
    }
}
