import AppKit
import SwiftUI

@MainActor
final class CompletionOverlayController: NSWindowController {
    private let overlayWindow: NSWindow
    private let onRestart: () -> Void
    private let onDismiss: () -> Void

    init(onRestart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onRestart = onRestart
        self.onDismiss = onDismiss

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rootView = CompletionOverlayView(
            onRestart: onRestart,
            onDismiss: onDismiss
        )

        overlayWindow = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.contentView = NSHostingView(rootView: rootView)

        super.init(window: overlayWindow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(playSound: Bool) {
        guard let screen = NSScreen.main else { return }
        overlayWindow.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        overlayWindow.makeKeyAndOrderFront(nil)
        if playSound {
            Self.playAlertBurst()
        }
    }

    func dismissOverlay() {
        overlayWindow.orderOut(nil)
    }

    static func playAlertBurst() {
        NSSound.beep()

        let names: [NSSound.Name] = [.init("Glass"), .init("Ping"), .init("Hero")]
        for (index, name) in names.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.45 * Double(index + 1))) {
                NSSound(named: name)?.play()
            }
        }
    }
}

private struct CompletionOverlayView: View {
    let onRestart: () -> Void
    let onDismiss: () -> Void

    @State private var pulse = false
    @State private var ringRotation = 0.0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.74))
                .ignoresSafeArea()

            Circle()
                .fill(Color.cyan.opacity(0.15))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .scaleEffect(pulse ? 1.12 : 0.92)

            VStack(spacing: 22) {
                ZStack {
                    ForEach(0 ..< 18, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(segmentColor(index: index))
                            .frame(width: 14, height: 40)
                            .offset(y: -108)
                            .rotationEffect(.degrees(Double(index) * 20))
                            .opacity(0.95)
                    }
                    .rotationEffect(.degrees(ringRotation))

                    OverlayCatBadge()
                }
                .frame(width: 260, height: 260)

                Text("专注完成")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("时间到了，起来活动一下，或者直接再来一轮。")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 16) {
                    Button("再来一轮") {
                        onRestart()
                    }
                    .buttonStyle(OverlayPrimaryButtonStyle())

                    Button("知道了") {
                        onDismiss()
                    }
                    .buttonStyle(OverlaySecondaryButtonStyle())
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    private func segmentColor(index: Int) -> Color {
        let fraction = Double(index) / 17.0
        if fraction < 0.33 {
            return Color(red: 0.47, green: 0.88, blue: 0.56)
        }
        if fraction < 0.66 {
            return Color(red: 0.98, green: 0.80, blue: 0.31)
        }
        return Color(red: 1.0, green: 0.39, blue: 0.36)
    }
}

private struct OverlayCatBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.95), Color(red: 0.45, green: 0.52, blue: 0.60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 78, height: 78)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.18, blue: 0.23), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 56, height: 56)

            HStack(spacing: 12) {
                Capsule(style: .continuous)
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.31))
                    .frame(width: 8, height: 18)

                Capsule(style: .continuous)
                    .fill(Color(red: 1.0, green: 0.72, blue: 0.31))
                    .frame(width: 8, height: 18)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(red: 1.0, green: 0.73, blue: 0.35)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 16
                    )
                )
                .frame(width: 26, height: 26)
                .offset(y: 18)

            OverlayTriangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 24, height: 22)
                .rotationEffect(.degrees(-14))
                .offset(x: -26, y: -28)

            OverlayTriangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 24, height: 22)
                .rotationEffect(.degrees(14))
                .offset(x: 26, y: -28)
        }
        .shadow(color: .white.opacity(0.14), radius: 18)
    }
}

private struct OverlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct OverlayPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.84))
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .opacity(configuration.isPressed ? 0.88 : 1.0)
            )
    }
}

private struct OverlaySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.10 : 0.06))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}
