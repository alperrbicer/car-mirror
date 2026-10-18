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

/// A light touch response for controls that supply their own surface and layout.
struct MirivoPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct MirivoSectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MirrorStyle.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A shared picture connects the TV, phone and unmistakable parked-car cockpit.
struct ScreenLinkIllustration: View {
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 340, geometry.size.height / 198)
            ZStack {
                Ellipse()
                    .fill(MirrorStyle.accent.opacity(active ? 0.24 : 0.15))
                    .frame(width: 275, height: 115)
                    .blur(radius: 30)
                    .position(x: 185, y: 112)
                Path { path in
                    path.move(to: CGPoint(x: 42, y: 142))
                    path.addCurve(to: CGPoint(x: 112, y: 68), control1: CGPoint(x: 6, y: 83), control2: CGPoint(x: 68, y: 57))
                    path.move(to: CGPoint(x: 57, y: 169))
                    path.addCurve(to: CGPoint(x: 215, y: 160), control1: CGPoint(x: 100, y: 210), control2: CGPoint(x: 148, y: 177))
                }
                .stroke(MirrorStyle.accent.opacity(active ? 0.8 : 0.42),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                SmartTVArtwork()
                    .frame(width: 180, height: 118)
                    .rotationEffect(.degrees(-5))
                    .position(x: 110, y: 65)
                CarPlayDashboardArtwork()
                    .frame(width: 254, height: 108)
                    .rotationEffect(.degrees(3))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 10)
                    .position(x: 208, y: 139)
                LinkedPhoneArtwork()
                    .frame(width: 44, height: 86)
                    .rotationEffect(.degrees(-9))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 4, y: 6)
                    .position(x: 43, y: 148)
                Circle().fill(MirrorStyle.accent).frame(width: 5, height: 5)
                    .position(x: 81, y: 181)
            }
            .frame(width: 340, height: 198)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 180)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct SmartTVArtwork: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 0.035, green: 0.055, blue: 0.06))
                ScreenLandscapeArtwork()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(5)
                    .padding(.bottom, 5)
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1, y: -3)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.2), in: Circle())
                VStack {
                    Spacer()
                    Text("Smart TV")
                        .font(.system(size: 6, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 2)
                }
            }
            .frame(height: 103)
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.10)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Path { path in
                path.move(to: CGPoint(x: 48, y: 0))
                path.addLine(to: CGPoint(x: 39, y: 12))
                path.addLine(to: CGPoint(x: 57, y: 12))
                path.move(to: CGPoint(x: 132, y: 0))
                path.addLine(to: CGPoint(x: 141, y: 12))
                path.addLine(to: CGPoint(x: 123, y: 12))
            }
            .stroke(Color(red: 0.43, green: 0.55, blue: 0.53), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(height: 15)
        }
    }
}

private struct CarPlayDashboardArtwork: View {
    var body: some View {
        ZStack {
            DashboardOutline()
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.29, blue: 0.28), Color(red: 0.07, green: 0.105, blue: 0.11), .black],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            DashboardOutline()
                .stroke(LinearGradient(colors: [.white.opacity(0.48), MirrorStyle.accent.opacity(0.16), .white.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            Capsule().fill(MirrorStyle.accent.opacity(0.5))
                .frame(width: 211, height: 1)
                .position(x: 128, y: 10)
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.65))
                .frame(width: 49, height: 24)
                .overlay {
                    HStack(spacing: 7) {
                        Circle().trim(from: 0.15, to: 0.85).stroke(MirrorStyle.accent.opacity(0.65), lineWidth: 1.5)
                        Circle().trim(from: 0.15, to: 0.85).stroke(MirrorStyle.accent.opacity(0.65), lineWidth: 1.5)
                    }.padding(6)
                }
                .position(x: 43, y: 36)
            Image(systemName: "steeringwheel")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.32)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 3)
                .position(x: 44, y: 60)
            carPlayDisplay
                .frame(width: 153, height: 72)
                .position(x: 166, y: 48)
            HStack(spacing: 8) {
                vent
                Image(systemName: "triangle.fill").font(.system(size: 5)).foregroundStyle(.white.opacity(0.5))
                vent
            }
            .frame(width: 110)
            .position(x: 166, y: 94)
        }
    }

    private var carPlayDisplay: some View {
        HStack(spacing: 4) {
            VStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(MirrorStyle.accent)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.65))
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(.white.opacity(0.65))
            }
            .font(.system(size: 9, weight: .medium))
            .frame(width: 13)
            ZStack {
                ScreenLandscapeArtwork()
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text("CarPlay").font(.system(size: 9, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(verbatim: "P")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .frame(width: 12, height: 12)
                            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .offset(x: 1)
                    Spacer(minLength: 0)
                    Capsule().fill(.white.opacity(0.25)).frame(height: 2)
                        .overlay(alignment: .leading) {
                            Capsule().fill(MirrorStyle.accent).frame(width: 30, height: 2)
                        }
                }
                .foregroundStyle(.white)
                .padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(5)
        .background(Color(red: 0.025, green: 0.04, blue: 0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.28)) }
    }

    private var vent: some View {
        VStack(spacing: 2) {
            Capsule().fill(.black.opacity(0.9)).frame(height: 2)
            Capsule().fill(.white.opacity(0.12)).frame(height: 1)
            Capsule().fill(.black.opacity(0.9)).frame(height: 2)
        }
    }
}

private struct DashboardOutline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.10, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.90, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.28), control: CGPoint(x: rect.width * 0.98, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.97, y: rect.height * 0.79))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.88, y: rect.height), control: CGPoint(x: rect.width * 0.96, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width * 0.12, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.03, y: rect.height * 0.79), control: CGPoint(x: rect.width * 0.04, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height * 0.28))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.10, y: 0), control: CGPoint(x: rect.width * 0.02, y: 0))
            path.closeSubpath()
        }
    }
}

private struct LinkedPhoneArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.025, green: 0.045, blue: 0.05))
            ScreenLandscapeArtwork().clipShape(RoundedRectangle(cornerRadius: 7)).padding(4)
            VStack {
                Capsule().fill(.black.opacity(0.8)).frame(width: 15, height: 4)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Capsule().fill(.white.opacity(0.65)).frame(width: 16, height: 2)
            }.padding(.vertical, 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
        }
    }
}

/// Matching abstract scenery makes the three displays read as one experience.
private struct ScreenLandscapeArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.09, green: 0.36, blue: 0.37), Color(red: 0.10, green: 0.20, blue: 0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(red: 0.72, green: 0.96, blue: 0.82))
                    .frame(width: height * 0.24, height: height * 0.24)
                    .blur(radius: 0.5)
                    .position(x: width * 0.76, y: height * 0.27)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.82))
                    path.addCurve(to: CGPoint(x: width, y: height * 0.33),
                                  control1: CGPoint(x: width * 0.28, y: -height * 0.02),
                                  control2: CGPoint(x: width * 0.55, y: height * 0.98))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [MirrorStyle.accent.opacity(0.9), Color(red: 0.08, green: 0.39, blue: 0.36)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.88))
                    path.addCurve(to: CGPoint(x: width, y: height * 0.67),
                                  control1: CGPoint(x: width * 0.48, y: height * 0.98),
                                  control2: CGPoint(x: width * 0.6, y: height * 0.28))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.36, blue: 0.32), Color(red: 0.025, green: 0.12, blue: 0.16)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }
}
