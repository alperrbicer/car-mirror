import XCTest
@testable import MirrorCore

final class CarPlayCapabilitiesTests: XCTestCase {
    func testAudioApprovalNeverEnablesVideoEvenInACapableVehicle() {
        let audio = CarPlayCapabilities(info: ["CMCarPlayAudioEnabled": "YES", "CMCarPlayVideoEnabled": "NO"])
        XCTAssertTrue(audio.audio)
        XCTAssertFalse(audio.video)
        for vehicle: Bool? in [true, false, nil] {
            XCTAssertFalse(audio.canPresentVideo(vehicleSupportsVideo: vehicle))
        }
    }

    func testVideoRequiresBothBuildCapabilitiesAndVehicleSupport() {
        let video = CarPlayCapabilities(info: ["CMCarPlayAudioEnabled": true, "CMCarPlayVideoEnabled": true])
        XCTAssertTrue(video.canPresentVideo(vehicleSupportsVideo: true))
        XCTAssertFalse(video.canPresentVideo(vehicleSupportsVideo: false))
        XCTAssertFalse(video.canPresentVideo(vehicleSupportsVideo: nil))
        let missingAudio = CarPlayCapabilities(info: ["CMCarPlayVideoEnabled": "YES"])
        XCTAssertFalse(missingAudio.canPresentVideo(vehicleSupportsVideo: true))
    }

    func testMissingPreviewAndUnresolvedFlagsKeepCarPlayDisabled() {
        for info: [String: Any] in [[:], ["CMCarPlayAudioEnabled": "NO", "CMCarPlayVideoEnabled": "NO"],
                                    ["CMCarPlayAudioEnabled": "$(MIRIVO_CARPLAY_AUDIO_ENABLED)", "CMCarPlayVideoEnabled": "YES"]] {
            let capabilities = CarPlayCapabilities(info: info)
            XCTAssertFalse(capabilities.audio)
            XCTAssertFalse(capabilities.video)
        }
    }
}
