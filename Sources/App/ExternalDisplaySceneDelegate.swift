import UIKit
import SwiftUI
import AVKit
import CarPlay

/// Only handles screens that iOS actually supplies.
@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let diagnosticID = UUID()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let screen = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: screen)
        window.rootViewController = UIHostingController(rootView: ExternalDisplayProbeView(model: .shared))
        window.isHidden = false
        self.window = window
        MirrorModel.shared.externalScreenConnected(diagnosticID,
            role: Self.displayRole(role: session.role, idiom: screen.traitCollection.userInterfaceIdiom),
            size: screen.screen.bounds.size)
    }

    static func displayRole(role: UISceneSession.Role, idiom: UIUserInterfaceIdiom) -> DiagnosticValues.Screen {
        // CarPlay Simulator can supply an ordinary external-display scene.
        // Its car idiom still identifies the destination without guessing from size.
        if idiom == .carPlay || role == .carTemplateApplication || role.rawValue == "UIWindowSceneSessionRoleCarPlay" {
            return .carPlay
        }
        return role == .windowExternalDisplayNonInteractive ? .externalNonInteractive : .externalInteractive
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true
        window = nil
        MirrorModel.shared.externalScreenDisconnected(diagnosticID)
    }
}

/// Some iOS CarPlay sessions supply a UIWindowScene rather than the template
/// scene. Own only that otherwise-empty, system-provided car window; never
/// replace the phone, an external-display delegate, or a template scene.
@MainActor
final class CarPlayWindowCoordinator: NSObject {
    static let shared = CarPlayWindowCoordinator()
    private var started = false
    private var presentations: [String: (window: UIWindow, diagnosticID: UUID)] = [:]

    func start() {
        guard !started else { return }
        started = true
        for name in [UIScene.willConnectNotification, UIScene.didActivateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sceneAvailable(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDisconnected(_:)),
                                               name: UIScene.didDisconnectNotification, object: nil)
        UIApplication.shared.connectedScenes.forEach(attach)
    }

    static func shouldAttach(role: UISceneSession.Role, idiom: UIUserInterfaceIdiom,
                             hasDelegate: Bool, hasWindows: Bool) -> Bool {
        idiom == .carPlay && role != .windowApplication && role != .carTemplateApplication &&
            role != .windowExternalDisplay && role != .windowExternalDisplayNonInteractive &&
            !hasDelegate && !hasWindows
    }

    @objc private func sceneAvailable(_ notification: Notification) {
        guard let scene = notification.object as? UIScene else { return }
        attach(scene)
    }

    private func attach(_ scene: UIScene) {
        guard let scene = scene as? UIWindowScene else { return }
        let id = scene.session.persistentIdentifier
        guard presentations[id] == nil,
              Self.shouldAttach(role: scene.session.role, idiom: scene.traitCollection.userInterfaceIdiom,
                                hasDelegate: scene.delegate != nil, hasWindows: !scene.windows.isEmpty) else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ExternalDisplayProbeView(model: .shared))
        let diagnosticID = UUID()
        presentations[id] = (window, diagnosticID)
        window.isHidden = false
        MirrorModel.shared.externalScreenConnected(diagnosticID, role: .carPlay, size: scene.screen.bounds.size)
    }

    @objc private func sceneDisconnected(_ notification: Notification) {
        guard let scene = notification.object as? UIScene,
              let presentation = presentations.removeValue(forKey: scene.session.persistentIdentifier) else { return }
        presentation.window.isHidden = true
        presentation.window.rootViewController = nil
        MirrorModel.shared.externalScreenDisconnected(presentation.diagnosticID)
    }
}

private struct ExternalDisplayProbeView: View {
    @ObservedObject var model: MirrorModel
    @ObservedObject private var playback = MirrorModel.shared.playback
    @AppStorage("language", store: SharedPreferences.defaults) private var language = "system"
    @AppStorage("player.videoDisplayMode") private var videoDisplayMode = PlayerVideoDisplayMode.normal

    var body: some View {
        ZStack {
            Color.black
            if let started = model.probeStartedAt { ConnectionPatternView(startedAt: started) }
            else if model.readyToPlay || model.mediaTitle != nil {
                MediaVideoView(playback: playback, role: .external, displayMode: videoDisplayMode, showsControls: false)
            } else {
                VStack(spacing: 16) {
                    MirrorMark().frame(width: 72, height: 72)
                    Text(BrandIdentity.name).font(.largeTitle)
                    Text(L10n.tr("iPhone’da ekran paylaşımını başlat.")).foregroundStyle(.secondary)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.locale, Locale(identifier: L10n.language))
        .environment(\.layoutDirection, L10n.appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        .id(language)
    }
}

struct ConnectionPatternView: View {
    let startedAt: Date
    private let colors: [Color] = [.white, .yellow, .cyan, .green, Color(red: 1, green: 0, blue: 1), .red, .blue]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let progress = CGFloat(elapsed.truncatingRemainder(dividingBy: 3) / 3)
            GeometryReader { geometry in
                ZStack {
                    MirrorStyle.background
                    VStack(spacing: 18) {
                        Text(BrandIdentity.name).font(.system(size: 22, weight: .medium))
                        Text(String(format: "%06.2f", elapsed))
                            .font(.system(size: min(geometry.size.width / 6, geometry.size.height / 4), weight: .medium, design: .monospaced))
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in colors[index] }
                        }
                        .frame(width: geometry.size.width * 0.6, height: 20)
                    }
                    Circle()
                        .fill(MirrorStyle.accent)
                        .frame(width: 18, height: 18)
                        .position(x: 30 + (geometry.size.width - 60) * progress,
                                  y: geometry.size.height * 0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel(L10n.tr("Hareketli ekran bağlantı testi"))
    }
}
