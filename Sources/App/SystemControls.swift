import SwiftUI
import ReplayKit
import AVKit

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        view.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "CMBroadcastExtensionIdentifier") as? String
        view.showsMicrophoneButton = false
        view.tintColor = .white
        view.accessibilityLabel = "Ekran yayınını başlat veya durdur"
        return view
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {}
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .systemMint
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

struct StreamPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
