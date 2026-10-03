import SwiftUI

enum MirrorStyle {
    static let background = Color("AppBackground")
    static let accent = Color("AccentColor")
    static let secondary = Color(red: 0.61, green: 0.66, blue: 0.67)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.10)
    static let raised = Color(red: 0.11, green: 0.135, blue: 0.14)
    static let hairline = Color.white.opacity(0.09)
    static let controlHeight: CGFloat = 58
}

/// Mirivo's overlapping screens and car share one vector source with the app icon.
struct MirrorMark: View {
    var body: some View {
        Image("MirivoMark")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct MirivoButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: MirrorStyle.controlHeight)
            .foregroundStyle(prominent ? MirrorStyle.background : .white)
            .background(prominent ? MirrorStyle.accent : MirrorStyle.raised, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(prominent ? .clear : MirrorStyle.hairline) }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct MirivoSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(L10n.appLanguage.allowsLetterSpacing ? 1.6 : 0)
            .foregroundStyle(MirrorStyle.secondary)
            .textCase(.uppercase)
    }
}

/// A continuous mint path visually joins the phone and the receiving display.
struct ScreenLinkIllustration: View {
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 320, 1.25)
            ZStack {
                Ellipse()
                    .fill(MirrorStyle.accent.opacity(active ? 0.15 : 0.07))
                    .frame(width: 240, height: 120)
                    .blur(radius: 28)
                    .offset(x: 22, y: 8)
                Path { path in
                    path.move(to: CGPoint(x: 80, y: 117))
                    path.addCurve(to: CGPoint(x: 238, y: 83), control1: CGPoint(x: 136, y: 176), control2: CGPoint(x: 155, y: 37))
                }
                .stroke(MirrorStyle.accent.opacity(active ? 0.8 : 0.38), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 6]))
                .frame(width: 320, height: 180)
                RoundedRectangle(cornerRadius: 19)
                    .fill(LinearGradient(colors: [MirrorStyle.raised, MirrorStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.17)) }
                    .frame(width: 194, height: 116)
                    .overlay {
                        ZStack {
                            MirrorMark().frame(width: 48, height: 48).opacity(active ? 1 : 0.6)
                            VStack {
                                HStack {
                                    Circle().fill(MirrorStyle.accent.opacity(active ? 1 : 0.3)).frame(width: 4, height: 4)
                                    Spacer()
                                    Capsule().fill(.white.opacity(0.12)).frame(width: 22, height: 3)
                                }
                                Spacer()
                                Capsule().fill(.white.opacity(0.08)).frame(height: 3)
                            }.padding(14)
                        }
                    }
                    .rotationEffect(.degrees(5))
                    .offset(x: 44, y: -13)
                RoundedRectangle(cornerRadius: 17)
                    .fill(MirrorStyle.background)
                    .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.4), lineWidth: 1.4) }
                    .frame(width: 70, height: 132)
                    .overlay {
                        VStack(spacing: 0) {
                            Capsule().fill(.white.opacity(0.25)).frame(width: 20, height: 4)
                            Spacer()
                            MirrorMark().frame(width: 35, height: 35)
                            Spacer()
                            Capsule().fill(.white.opacity(0.2)).frame(width: 21, height: 3)
                        }.padding(.vertical, 11)
                    }
                    .rotationEffect(.degrees(-8))
                    .offset(x: -91, y: 12)
                Circle().fill(MirrorStyle.accent).frame(width: 7, height: 7).offset(x: -3, y: 41)
            }
            .frame(width: 320, height: 180)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 186)
        .accessibilityHidden(true)
    }
}
