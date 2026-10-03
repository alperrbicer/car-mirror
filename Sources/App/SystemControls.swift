import SwiftUI
import ReplayKit

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> CenteredBroadcastPickerView {
        let view = CenteredBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        view.picker.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "CMBroadcastExtensionIdentifier") as? String
        view.picker.showsMicrophoneButton = false
        view.picker.tintColor = UIColor(red: 0.035, green: 0.043, blue: 0.051, alpha: 1)
        view.picker.accessibilityIdentifier = "broadcast-picker"
        view.picker.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
        return view
    }
    func updateUIView(_ view: CenteredBroadcastPickerView, context: Context) {
        view.picker.accessibilityLabel = L10n.tr("Ekran yayınını başlat veya durdur")
        view.setNeedsLayout()
    }
}

final class CenteredBroadcastPickerView: UIView {
    // Host the concrete ReplayKit control so its native artwork and action stay intact.
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(picker)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        picker.layoutIfNeeded()

        // ReplayKit can retain its button's initial frame after SwiftUI resizes the picker.
        // Keep the native button and its system action, but fit it to the current bounds.
        for case let button as UIButton in picker.subviews {
            button.frame = bounds
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            button.accessibilityIdentifier = picker.accessibilityIdentifier
            button.accessibilityLabel = picker.accessibilityLabel
        }
    }
}
