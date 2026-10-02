import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        view.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "CMBroadcastExtensionIdentifier") as? String
        view.showsMicrophoneButton = false
        view.tintColor = .white
        view.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
        return view
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        view.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
    }
}
