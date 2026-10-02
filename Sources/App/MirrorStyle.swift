import SwiftUI

enum MirrorStyle {
    static let background = Color("AppBackground")
    static let accent = Color("AccentColor")
    static let secondary = Color(red: 0.59, green: 0.63, blue: 0.66)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.10)
}

/// Two offset screens with a car in front, shared with the app icon.
struct MirrorMark: View {
    var body: some View {
        Image("MirivoMark")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct ScreenLinkIllustration: View {
    let active: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(MirrorStyle.accent.opacity(active ? 0.09 : 0.035))
                .frame(width: 220, height: 115)
                .blur(radius: 32)
                .offset(y: 42)
            RoundedRectangle(cornerRadius: 24)
                .fill(MirrorStyle.surface)
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1) }
                .frame(width: 218, height: 130)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Capsule().fill(MirrorStyle.accent.opacity(active ? 0.9 : 0.35)).frame(width: 5, height: CGFloat(10 + index * 5))
                        }
                    }.padding(18)
                }
                .offset(x: 23, y: -10)
            RoundedRectangle(cornerRadius: 21)
                .fill(MirrorStyle.background)
                .overlay { RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.25), lineWidth: 1) }
                .frame(width: 85, height: 146)
                .overlay {
                    VStack(spacing: 20) {
                        Capsule().fill(.white.opacity(0.3)).frame(width: 23, height: 4)
                        MirrorMark().foregroundStyle(MirrorStyle.accent).frame(width: 32, height: 32)
                        Capsule().fill(.white.opacity(0.13)).frame(width: 25, height: 3)
                    }
                }
                .rotationEffect(.degrees(-8))
                .offset(x: -74, y: 25)
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }
}
