import Foundation

/// The selected build declares which entitlements its signature must contain.
/// Vehicle video support alone never enables an audio-only build's video path.
struct CarPlayCapabilities: Equatable {
    let audio: Bool
    let video: Bool

    static var current: Self { Self(info: Bundle.main.infoDictionary ?? [:]) }

    init(info: [String: Any]) {
        func enabled(_ key: String) -> Bool {
            if let value = info[key] as? String { return value == "YES" }
            return info[key] as? Bool == true
        }
        audio = enabled("CMCarPlayAudioEnabled")
        video = audio && enabled("CMCarPlayVideoEnabled")
    }

    func canPresentVideo(vehicleSupportsVideo: Bool?) -> Bool {
        video && vehicleSupportsVideo == true
    }
}

enum MediaPlaybackPresentation {
    case audio, video
}
