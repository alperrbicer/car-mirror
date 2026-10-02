import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> CenteredBroadcastPickerView {
        let view = CenteredBroadcastPickerView(frame: .zero)
        view.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "CMBroadcastExtensionIdentifier") as? String
        view.showsMicrophoneButton = false
        view.tintColor = UIColor(red: 0.035, green: 0.043, blue: 0.051, alpha: 1)
        view.accessibilityIdentifier = "broadcast-picker"
        view.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
        return view
    }
    func updateUIView(_ view: CenteredBroadcastPickerView, context: Context) {
        view.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
    }
}

final class CenteredBroadcastPickerView: RPSystemBroadcastPickerView {
    override func layoutSubviews() {
        super.layoutSubviews()

        // ReplayKit can retain its button's initial frame after SwiftUI resizes the picker.
        // Keep the native button and its system action, but fit it to the current bounds.
        for case let button as UIButton in subviews {
            button.frame = bounds
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
        }
    }
}
