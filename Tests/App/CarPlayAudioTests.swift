import XCTest
import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
@preconcurrency import VLCKit
@testable import CarMirror

@MainActor
final class CarPlayAudioTests: XCTestCase {
    func testPlayingCompatibilityVideoContinuesAfterSeeking() async throws {
        try await checkPlayingVideoSeeks(useCompatibility: true)
    }

    func testPlayingNativeVideoContinuesAfterSeeking() async throws {
        try await checkPlayingVideoSeeks(useCompatibility: false)
    }

    func testOptInProviderMKVSeeksWhilePlaying() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-vod-probe.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("No opt-in MKV fixture") }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        try await checkPlayingVideoSeeks(useCompatibility: true, providerURL: XCTUnwrap(urls["original"]))
    }

    private func checkPlayingVideoSeeks(useCompatibility: Bool, providerURL: URL? = nil) async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(providerURL ?? (useCompatibility
            ? Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")
            : Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Seek fixture", url: url)))
        let playback = model.playback
        let engine = playback.compatibility
        let item = playback.player.currentItem
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item?.add(output)
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<(providerURL == nil ? 150 : 600) {
            if playback.isPlaying && playback.canSeek && playback.currentTime > 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.canSeek)

        // Exercise forward, backward, and overlapping seeks while decoding real video.
        let seeks = providerURL == nil ? [[6.0], [2.0], [3.0, 5.0, 8.0], [2.0, 4.0, 6.0]] : [[120.0], [30.0], [300.0, 600.0, 900.0], [60.0, 180.0, 240.0]]
        for (index, targets) in seeks.enumerated() {
            let target = try XCTUnwrap(targets.last)
            let started = ContinuousClock.now
            for value in targets {
                playback.seek(to: value)
                // Also queue a newer target after the preceding jump has begun.
                if index == 3 { try await Task.sleep(for: .milliseconds(180)) }
            }
            for sample in 0..<(providerURL == nil ? 100 : 400) {
                if playback.currentTime > target + 0.6 && playback.currentTime < target + 3 { break }
                if providerURL != nil, sample.isMultiple(of: 40), let engine, let statistics = engine.mediaPlayer.media?.statistics {
                    print("Seek sample: target=\(target), engineTime=\(engine.mediaTime()), read=\(statistics.readBytes), demux=\(statistics.demuxReadBytes), decoded=\(statistics.decodedVideo), displayed=\(statistics.displayedPictures)")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertTrue(playback.isPlaying, "Seeking during playback must preserve play intent")
            XCTAssertGreaterThan(playback.currentTime, target + 0.5, "The timeline must continue after seeking")
            XCTAssertLessThan(playback.currentTime, target + 3, "The newest requested position must win")
            XCTAssertTrue(playback.compatibility === engine)
            XCTAssertTrue(playback.player.currentItem === item)
            if providerURL != nil {
                print("Seek probe: target=\(target), actual=\(playback.currentTime), elapsed=\(started.duration(to: .now)), pictures=\(engine?.mediaPlayer.media?.statistics.displayedPictures ?? 0)")
            }

            if let engine {
                let pictures = engine.mediaPlayer.media?.statistics.displayedPictures ?? 0
                try await Task.sleep(for: .milliseconds(1100))
                XCTAssertGreaterThan(engine.mediaPlayer.media?.statistics.displayedPictures ?? 0, pictures,
                                     "Decoded video must keep reaching the display, not only advance its clock")
            } else if let item {
                var firstTime = CMTime.invalid
                var nextTime = CMTime.invalid
                XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &firstTime))
                try await Task.sleep(for: .milliseconds(600))
                XCTAssertNotNil(output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &nextTime))
                XCTAssertGreaterThan(nextTime.seconds, firstTime.seconds + 0.3,
                                     "The native video output must produce new frames after seeking")
            }
        }
        if useCompatibility, let engine {
            playback.togglePlayPause()
            for _ in 0..<60 {
                if !playback.isPlaying { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            // An unchanged position must not block the next real seek.
            playback.seek(to: Double(engine.mediaTime()) / 1000)
            try await Task.sleep(for: .milliseconds(250))
            playback.seek(to: providerURL == nil ? 4 : 60)
            for _ in 0..<(providerURL == nil ? 100 : 200) {
                if abs(Double(engine.mediaTime()) / 1000 - (providerURL == nil ? 4 : 60)) < 0.1 { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(Double(engine.mediaTime()) / 1000, providerURL == nil ? 4 : 60, accuracy: 0.1)
            XCTAssertFalse(playback.isPlaying, "Queued seeking must not resume an explicitly paused video")
        }
        if providerURL == nil {
            capturePlayer(host.view, name: useCompatibility ? "mkv-after-playing-seeks" : "mp4-after-playing-seeks")
        }
    }

    func testFullscreenVideoUsesEntireViewportAfterRotation() async throws {
        try await checkFullscreenRotation(useCompatibility: true)
    }

    func testNativeFullscreenVideoUsesEntireViewportAfterRotation() async throws {
        try await checkFullscreenRotation(useCompatibility: false)
    }

    private func checkFullscreenRotation(useCompatibility: Bool) async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(useCompatibility
            ? Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv")
            : Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Fullscreen fixture", url: url)))
        let engine = model.playback.compatibility
        let nativeItem = model.playback.player.currentItem
        XCTAssertEqual(engine != nil, useCompatibility)
        for vehicleMode in [false, true] {
            let host = UIHostingController(rootView: VehicleModeView(vehicleMode: vehicleMode, model: model, close: {}))
            window.rootViewController = host
            window.makeKeyAndVisible()
            for orientation: UIInterfaceOrientationMask in [.portrait, .landscapeLeft, .landscapeRight, .portrait] {
                var rotationError: Error?
                host.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { rotationError = $0 }
                let landscape = orientation != .portrait
                for _ in 0..<100 {
                    if (window.bounds.width > window.bounds.height) == landscape { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try await Task.sleep(for: .milliseconds(450))
                // Keep the short fixture on screen throughout both mode/rotation cycles.
                if model.playback.isPlaying {
                    model.playback.togglePlayPause()
                    for _ in 0..<40 {
                        if !model.playback.isPlaying { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
                host.view.layoutIfNeeded()
                XCTAssertNil(rotationError)
                XCTAssertEqual(window.bounds.width > window.bounds.height, landscape)
                let compatibilityView: UIView? = engine?.videoView
                let video = try XCTUnwrap(compatibilityView ?? nativeVideoController(in: host)?.view)
                XCTAssertTrue(video.window === window)
                XCTAssertEqual(video.bounds.width, window.bounds.width, accuracy: 1)
                XCTAssertEqual(video.bounds.height, window.bounds.height, accuracy: 1,
                               "Player chrome must overlay the video, without reducing its height")
                for renderer in engine?.videoView.subviews ?? [] {
                    XCTAssertEqual(renderer.bounds.width, window.bounds.width, accuracy: 1)
                    XCTAssertEqual(renderer.bounds.height, window.bounds.height, accuracy: 1)
                }
                XCTAssertTrue(model.playback.compatibility === engine)
                XCTAssertTrue(model.playback.player.currentItem === nativeItem, "Rotation must not restart playback")
                if orientation == .landscapeLeft {
                    let name = "\(useCompatibility ? "mkv" : "native")-\(vehicleMode ? "vehicle" : "fullscreen")-landscape"
                    capturePlayer(host.view, name: name)
                    if !vehicleMode {
                        model.playback.resume()
                        for _ in 0..<40 {
                            if model.playback.isPlaying { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try await Task.sleep(for: .milliseconds(4700))
                        XCTAssertTrue(model.playback.isPlaying)
                        XCTAssertEqual(video.bounds.size, window.bounds.size, "Hiding controls must not resize video")
                        capturePlayer(host.view, name: "\(name)-unobstructed")
                        model.playback.togglePlayPause()
                    }
                }
            }
        }
    }

    private func nativeVideoController(in controller: UIViewController) -> AVPlayerViewController? {
        if let player = controller as? AVPlayerViewController { return player }
        return controller.children.lazy.compactMap { self.nativeVideoController(in: $0) }.first
    }

    private func capturePlayer(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image {
            _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompatibilityVideoHasVisibleInlineOutputBeforeFullscreen() async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Inline fixture", url: url)))
        let engine = try XCTUnwrap(model.playback.compatibility)
        // The existing source-list preview gets the drawable before navigation.
        try await Task.sleep(for: .milliseconds(350))
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(700))
        for _ in 0..<150 {
            if model.playback.currentTime > 0.3 && engine.mediaPlayer.hasVideoOut { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertTrue(engine.mediaPlayer.hasVideoOut)
        XCTAssertTrue(engine.videoView.window === window)
        XCTAssertGreaterThan(engine.videoView.bounds.width, 100)
        XCTAssertGreaterThan(engine.videoView.bounds.height, 80)
        XCTAssertFalse(engine.videoView.subviews.isEmpty)
        for renderView in engine.videoView.subviews {
            XCTAssertEqual(renderView.frame.size.width, engine.videoView.bounds.width, accuracy: 1)
            XCTAssertEqual(renderView.frame.size.height, engine.videoView.bounds.height, accuracy: 1)
        }
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(200))
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let snapshot = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "inline-video-first-open"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompatibilityPiPReturnClearsStaleRendererMask() async throws {
        let model = MirrorModel.shared
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InlineVideo", withExtension: "mkv"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        defer {
            model.stopPlayback()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "PiP video", url: url)))
        let engine = try XCTUnwrap(model.playback.compatibility)
        let host = UIHostingController(rootView: NavigationStack { MediaPlayerScreen(model: model) })
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<150 {
            if model.playback.currentTime > 0.3 && engine.mediaPlayer.hasVideoOut { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(300))
        func videoLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
            if let video = layer as? AVSampleBufferDisplayLayer { return video }
            return layer.sublayers?.lazy.compactMap { videoLayer(in: $0) }.first
        }
        let video = try XCTUnwrap(videoLayer(in: engine.videoView.layer))
        // The simulator's VLC build has no system PiP controller. Exercise its
        // didStart/didStop callback contract against the actual decoding layer.
        let pip = PictureInPictureStub()
        engine.configurePiP(pip)
        pip.startPictureInPicture()
        await Task.yield()
        XCTAssertTrue(engine.pipActive)
        let transitionMask = CAShapeLayer()
        transitionMask.path = UIBezierPath(roundedRect: video.bounds, byRoundingCorners: .topLeft,
                                          cornerRadii: CGSize(width: 64, height: 64)).cgPath
        video.mask = transitionMask
        video.cornerRadius = 64
        video.maskedCorners = [.layerMinXMinYCorner]
        let rounding = CABasicAnimation(keyPath: "cornerRadius")
        rounding.fromValue = 64; rounding.toValue = 64; rounding.duration = 10
        video.add(rounding, forKey: "cornerRadius")
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        XCTAssertTrue(video.mask === transitionMask, "Active PiP must retain its transition clipping")
        XCTAssertNotNil(video.animation(forKey: "cornerRadius"))
        pip.stopPictureInPicture()
        await Task.yield()
        XCTAssertFalse(engine.pipActive)
        XCTAssertNil(video.mask, "A completed PiP return must remove the temporary one-corner mask")
        XCTAssertEqual(video.cornerRadius, 0)
        XCTAssertEqual(video.maskedCorners, [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                           .layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        XCTAssertNil(video.animation(forKey: "cornerRadius"))
        XCTAssertTrue(engine.videoView.window === window)
        XCTAssertTrue(model.playback.compatibility === engine)
        XCTAssertFalse(model.playback.isPlaying, "Restoration must preserve an explicit pause")
        capturePlayer(host.view, name: "inline-player-restored-clipping")
    }

    private final class PictureInPictureStub: NSObject, VLCPictureInPictureWindowControlling {
        var stateChangeEventHandler: ((Bool) -> Void)?
        func startPictureInPicture() { stateChangeEventHandler?(true) }
        func stopPictureInPicture() { stateChangeEventHandler?(false) }
        func invalidatePlaybackState() {}
    }

    func testCompatibilityVideoOwnershipSurvivesPreviewUpdatesAndFullscreenReturn() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIViewController()
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let root = try XCTUnwrap(window.rootViewController?.view)
        let engine = CompatibilityPlayback()
        let preview = CompatibilityVideoHost(frame: CGRect(x: 0, y: 0, width: 88, height: 50))
        preview.configure(engine: engine, role: .preview, fillsFrame: false)
        root.addSubview(preview)
        XCTAssertTrue(engine.videoView.superview === preview)

        // Do not move the renderer into an inline host until it has real bounds.
        let inline = CompatibilityVideoHost()
        inline.configure(engine: engine, role: .inline, fillsFrame: false)
        root.addSubview(inline)
        XCTAssertTrue(engine.videoView.superview === preview)
        inline.frame = CGRect(x: 0, y: 100, width: 320, height: 180)
        inline.layoutIfNeeded()
        XCTAssertTrue(engine.videoView.superview === inline)
        XCTAssertEqual(engine.videoView.bounds.size, inline.bounds.size)

        preview.configure(engine: engine, role: .preview, fillsFrame: false)
        XCTAssertTrue(engine.videoView.superview === inline, "A stale preview update must not steal the video")
        let fullscreen = CompatibilityVideoHost(frame: root.bounds)
        fullscreen.configure(engine: engine, role: .fullscreen, fillsFrame: true)
        root.addSubview(fullscreen)
        inline.configure(engine: engine, role: .inline, fillsFrame: false)
        XCTAssertTrue(engine.videoView.superview === fullscreen)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .larger)
        fullscreen.detach()
        XCTAssertTrue(engine.videoView.superview === inline)
        XCTAssertEqual(engine.mediaPlayer.videoFitMode, .smaller)
        inline.removeFromSuperview()
        XCTAssertTrue(engine.videoView.superview === preview, "Returning to the list must restore its preview")
        fullscreen.removeFromSuperview()
        XCTAssertTrue(engine.videoView.superview === preview, "Late teardown must not detach the new owner")
        preview.detach()
        XCTAssertNil(engine.videoView.superview)
    }

    func testNativeTimelineShowsDurationSeeksWhilePausedAndResets() async throws {
        let url = try audioFixture()
        let playback = PlaybackController()
        defer { playback.stop(); try? FileManager.default.removeItem(at: url) }
        // Metadata must identify finite media even when its URL was classified as live.
        try playback.play(url: url, requiresExternalPlayback: false, live: true, presentation: .audio)
        for _ in 0..<100 {
            if playback.currentTime > 0.1 && playback.canSeek { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(playback.currentTime, 0.1)
        XCTAssertEqual(playback.duration, 10, accuracy: 0.1)
        XCTAssertFalse(playback.isLive)
        XCTAssertTrue(playback.canSeek)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        playback.seek(to: 6)
        for _ in 0..<100 {
            if abs(playback.player.currentTime().seconds - 6) < 0.1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(playback.player.currentTime().seconds, 6, accuracy: 0.1)
        XCTAssertEqual(playback.currentTime, 6, accuracy: 0.1)
        XCTAssertFalse(playback.isPlaying, "Seeking must not undo a user pause")
        let metadata = MPNowPlayingInfoCenter.default().nowPlayingInfo
        XCTAssertEqual(metadata?[MPMediaItemPropertyPlaybackDuration] as? Double, 10)
        XCTAssertEqual(metadata?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false)
        playback.stop()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertEqual(playback.duration, 0)
        XCTAssertFalse(playback.canSeek)
    }

    func testCompatibilityTimelineSeeksAndIgnoresReplacedEngine() async throws {
        let url = try audioFixture()
        let playback = PlaybackController()
        defer { playback.stop(); try? FileManager.default.removeItem(at: url) }
        try playback.play(url: url, requiresExternalPlayback: false, live: false, presentation: .audio, useCompatibility: true)
        let engine = try XCTUnwrap(playback.compatibility)
        for _ in 0..<150 {
            if playback.currentTime > 0.1 && playback.canSeek { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(playback.currentTime, 0.1)
        XCTAssertEqual(playback.duration, 10, accuracy: 0.1)
        XCTAssertFalse(playback.isLive)
        XCTAssertTrue(playback.canSeek)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(200))
        playback.seek(to: 6)
        for _ in 0..<100 {
            if abs(Double(engine.mediaTime()) / 1000 - 6) < 0.25 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(Double(engine.mediaTime()) / 1000, 6, accuracy: 0.25)
        XCTAssertFalse(playback.isPlaying)
        try playback.play(url: url, requiresExternalPlayback: false, live: true, presentation: .audio)
        engine.onTime?(99, 100)
        XCTAssertEqual(playback.currentTime, 0)
        XCTAssertEqual(playback.duration, 0)
        XCTAssertTrue(playback.isLive)
    }

    func testAudioPlaybackPublishesAudioMetadataAndCleansUpControls() async throws {
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false,
                          title: "Audio test", live: false, presentation: .audio)
        for _ in 0..<100 {
            if playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
        XCTAssertEqual(AVAudioSession.sharedInstance().mode, .default)
        XCTAssertEqual(AVAudioSession.sharedInstance().routeSharingPolicy, .longFormAudio)
        let center = MPNowPlayingInfoCenter.default()
        XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Audio test")
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue,
                       MPNowPlayingInfoMediaType.audio.rawValue)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual((center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue, 0)
        playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(MPRemoteCommandCenter.shared().stopCommand.isEnabled)
        playback.stop()
        XCTAssertNil(playback.player.currentItem)
        XCTAssertNil(center.nowPlayingInfo)
        XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
        XCTAssertFalse(MPRemoteCommandCenter.shared().stopCommand.isEnabled)
    }

    func testSwitchingFromVideoToAudioDisablesExternalVideoAndUpdatesMetadata() throws {
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        defer { playback.stop() }
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false, presentation: .video)
        XCTAssertTrue(playback.player.allowsExternalPlayback)
        try playback.play(url: url, preserveSourceAudio: false, requiresExternalPlayback: false, presentation: .audio)
        XCTAssertFalse(playback.player.allowsExternalPlayback)
        XCTAssertEqual((MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue,
                       MPNowPlayingInfoMediaType.audio.rawValue)
        XCTAssertEqual(AVAudioSession.sharedInstance().routeSharingPolicy, .longFormAudio)
    }

    func testVideoPlaysOnPhoneWithoutCarConnection() async throws {
        let model = MirrorModel.shared
        model.stopPlayback()
        defer { model.stopPlayback() }
        XCTAssertFalse(model.carPlayConnected)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ConnectionProbe", withExtension: "mp4"))
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Local video", url: url)))
        XCTAssertEqual(model.playback.state, .loading)
        XCTAssertFalse(model.playback.canUseVehicleMode)
        for _ in 0..<100 {
            if model.playback.isPlaying { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertEqual(model.playback.state, .playing)
        XCTAssertNil(model.mediaErrorMessage)
        XCTAssertFalse(model.playback.externalPlaybackActive)
        XCTAssertFalse(model.playback.player.isMuted)
    }

    func testFailedMediaClearsNowPlayingAndRetainsRetryAfterDismissingAlert() async throws {
        let model = MirrorModel.shared
        model.stopPlayback()
        defer { model.stopPlayback() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).mp4")
        let channel = MediaChannel(title: "Unavailable stream", url: url)
        XCTAssertTrue(model.playMedia(channel))
        for _ in 0..<100 {
            if model.playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.playback.state, .failed)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNil(model.playback.player.currentItem)
        XCTAssertFalse(model.playback.hasActivePlayback)
        XCTAssertFalse(model.playback.canUseVehicleMode)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertNotNil(model.errorMessage)
        model.errorMessage = nil
        XCTAssertNotNil(model.mediaErrorMessage)
        XCTAssertEqual(model.selectedMediaChannel, channel)
        model.retryMedia()
        XCTAssertEqual(model.playback.state, .loading)
        XCTAssertNotNil(model.playback.player.currentItem)
        XCTAssertNil(model.mediaErrorMessage)
        model.stopPlayback()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.playback.state, .idle)
        XCTAssertNil(model.selectedMediaChannel)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNil(model.mediaErrorMessage)
    }

    func testChannelQueuePreservesActiveSessionAndMovesBetweenChannels() throws {
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = MediaChannel(title: "Queue first", url: url)
        let second = MediaChannel(title: "Queue second", url: url.appendingPathComponent("second"))
        XCTAssertTrue(model.playMedia(first, queue: [first, second]))
        let item = try XCTUnwrap(model.playback.player.currentItem)
        XCTAssertTrue(model.playMedia(first))
        XCTAssertTrue(model.playback.player.currentItem === item)
        XCTAssertNil(model.adjacentChannel(-1))
        XCTAssertEqual(model.adjacentChannel(1), second)
        model.switchChannel(1)
        XCTAssertEqual(model.selectedMediaChannel, second)
        XCTAssertEqual(model.adjacentChannel(-1), first)
        XCTAssertNil(model.adjacentChannel(1))
    }

    func testChannelSelectionKeepsPiPRestoredPlayerPresented() throws {
        let model = MirrorModel.shared
        let url = try audioFixture()
        defer { model.stopPlayback(); try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "First", url: url)))
        model.playerVisibilityChanged(false)
        model.playback.onRestorePlayer? { _ in }
        XCTAssertTrue(model.presentingPlayer)
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Second", url: url)))
        XCTAssertTrue(model.presentingPlayer, "Picking a channel must keep the restored player's full-screen presentation open")
        XCTAssertEqual(model.mediaTitle, "Second")
    }

    func testLateFailureFromReplacedItemDoesNotStopNewPlayback() async throws {
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let url = try audioFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "First", url: url)))
        let oldItem = try XCTUnwrap(model.playback.player.currentItem)
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Second", url: url)))
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: oldItem)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.mediaTitle, "Second")
        XCTAssertNil(model.mediaErrorMessage)
        let currentItem = try XCTUnwrap(model.playback.player.currentItem)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: currentItem)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.playback.state, .failed)
        XCTAssertNil(model.mediaTitle)
        XCTAssertNotNil(model.mediaErrorMessage)
    }

    // Opt-in provider regression: a local, untracked fixture in the simulator app's tmp
    // directory supplies `ts` and `m3u8` URLs. Never put account URLs in test sources/logs.
    func testOptInProviderTransportStreamAndHLSPlayback() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-live-playback-fixture.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("No opt-in live provider fixture")
        }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        let transportStream = try XCTUnwrap(urls["ts"])
        let hls = try XCTUnwrap(urls["m3u8"])
        let playback = PlaybackController()
        defer { playback.stop() }
        var failure: DiagnosticFailure?
        playback.onDiagnostic = { kind, values in
            if kind == .failure { failure = values.failure }
        }
        try playback.play(url: transportStream, preserveSourceAudio: false, requiresExternalPlayback: false)
        for _ in 0..<200 {
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(playback.state, .failed)
        XCTAssertEqual(failure?.code, -11850)
        try playback.play(url: hls, preserveSourceAudio: false, requiresExternalPlayback: false)
        for _ in 0..<200 {
            if playback.isPlaying && playback.player.currentTime().seconds > 0.2 { break }
            if playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThan(playback.player.currentTime().seconds, 0.2)
        XCTAssertGreaterThan(playback.player.currentItem?.presentationSize.width ?? 0, 0)
        XCTAssertNil(playback.errorMessage)
    }

    func testSourceCacheReusesResultsAndInvalidatesOnEdit() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Fixture", kind: .playlist)
        let channel = MediaChannel(title: "One", url: URL(string: "https://example.com/one.m3u8")!)
        var requests = 0
        let first = try await cache.channels(for: source) { requests += 1; return [channel] }
        let second = try await cache.channels(for: source) { requests += 1; return [] }
        XCTAssertEqual(first, second)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(cache.cached(for: source), [channel])
        cache.invalidate(source.id)
        XCTAssertNil(cache.cached(for: source))
        _ = try await cache.channels(for: source) { requests += 1; return [channel] }
        XCTAssertEqual(requests, 2)
        cache.removeAll()
        XCTAssertNil(cache.cached(for: source))
    }

    func testSourceCacheCoalescesConcurrentLoads() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Concurrent", kind: .playlist)
        var requests = 0
        let first = Task { try await cache.channels(for: source) {
            requests += 1
            try await Task.sleep(for: .milliseconds(100))
            return []
        } }
        await Task.yield()
        let second = Task { try await cache.channels(for: source) { requests += 1; return [] } }
        _ = try await first.value; _ = try await second.value
        XCTAssertEqual(requests, 1)
    }

    func testSourceCacheDoesNotPublishAnInvalidatedInFlightResponse() async throws {
        let cache = SourceChannelCache()
        let source = MediaSource(name: "Invalidated", kind: .playlist)
        let channel = MediaChannel(title: "Old", url: URL(string: "https://example.com/old.m3u8")!)
        let old = Task { try await cache.channels(for: source) {
            try? await Task.sleep(for: .milliseconds(100))
            return [channel]
        } }
        try await Task.sleep(for: .milliseconds(20))
        cache.invalidate(source.id)
        do { _ = try await old.value; XCTFail("Invalidated response must be discarded") }
        catch is CancellationError { }
        XCTAssertNil(cache.cached(for: source))
        let fresh = try await cache.channels(for: source) { [] }
        XCTAssertTrue(fresh.isEmpty)
    }

    func testBackgroundPolicyAndPiPRestorationKeepCurrentItem() async throws {
        let model = MirrorModel.shared
        let url = try audioFixture()
        defer { model.stopPlayback(); try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(model.playMedia(MediaChannel(title: "Background", url: url)))
        let item = model.playback.player.currentItem
        XCTAssertEqual(model.playback.player.audiovisualBackgroundPlaybackPolicy, .continuesIfPossible)
        model.playerVisibilityChanged(false)
        var restored = false
        model.playback.onRestorePlayer? { restored = $0 }
        XCTAssertTrue(model.presentingPlayer)
        XCTAssertFalse(restored)
        model.playerVisibilityChanged(true)
        XCTAssertTrue(restored)
        XCTAssertTrue(item === model.playback.player.currentItem)
        model.presentingPlayer = false
        model.playerVisibilityChanged(false)
    }

    func testOptInProviderMKVPlayback() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-vod-probe.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("No opt-in MKV fixture") }
        let urls = try JSONDecoder().decode([String: URL].self, from: Data(contentsOf: fixture))
        let url = try XCTUnwrap(urls["original"])
        let model = MirrorModel.shared
        defer { model.stopPlayback() }
        let channel = MediaChannel(title: "MKV fixture", url: url)
        XCTAssertTrue(channel.requiresCompatibilityPlayback)
        XCTAssertFalse(channel.isLive)
        XCTAssertTrue(model.playMedia(channel))
        let engine = try XCTUnwrap(model.playback.compatibility)
        engine.videoView.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        for _ in 0..<300 {
            if model.playback.isPlaying && model.playback.currentTime > 0.2 { break }
            if model.playback.state == .failed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(model.playback.isPlaying)
        XCTAssertGreaterThan(model.playback.currentTime, 0.2)
        XCTAssertGreaterThan(engine.mediaPlayer.videoSize.width, 0)
        XCTAssertNil(model.mediaErrorMessage)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false)
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.playback.isPlaying)
        model.foregrounded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.playback.isPlaying, "Foregrounding must not undo a user pause")
        model.playback.togglePlayPause()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(model.playback.isPlaying)
    }

    private func audioFixture() throws -> URL {
        let samples = 44_100 * 10
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(36 + samples * 2)); text("WAVEfmt ")
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1)); word(UInt32(44_100))
        word(UInt32(88_200)); word(UInt16(2)); word(UInt16(16)); text("data"); word(UInt32(samples * 2))
        for index in 0..<samples { word(Int16(sin(Double(index) * 2 * .pi * 440 / 44_100) * 1_000)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-audio-test-\(UUID()).wav")
        try data.write(to: url)
        return url
    }
}
