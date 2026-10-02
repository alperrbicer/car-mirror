import UIKit
import SwiftUI

/// Only handles screens that iOS actually supplies. A CarPlay template is not a UIWindowScene.
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
            role: session.role == .windowExternalDisplayNonInteractive ? .externalNonInteractive : .externalInteractive,
            size: screen.screen.bounds.size)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window?.isHidden = true
        window = nil
        MirrorModel.shared.externalScreenDisconnected(diagnosticID)
    }
}

private struct ExternalDisplayProbeView: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        ZStack {
            Color.black
            if let started = model.probeStartedAt { ConnectionPatternView(startedAt: started) }
        }
        .ignoresSafeArea()
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
                    Color(red: 0.035, green: 0.05, blue: 0.07)
                    VStack(spacing: 18) {
                        Text("CarMirror").font(.system(size: 22, weight: .medium))
                        Text(String(format: "%06.2f", elapsed))
                            .font(.system(size: min(geometry.size.width / 6, geometry.size.height / 4), weight: .medium, design: .monospaced))
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in colors[index] }
                        }
                        .frame(width: geometry.size.width * 0.6, height: 20)
                    }
                    Circle()
                        .fill(Color.mint)
                        .frame(width: 18, height: 18)
                        .position(x: 30 + (geometry.size.width - 60) * progress,
                                  y: geometry.size.height * 0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Hareketli ekran bağlantı testi")
    }
}
