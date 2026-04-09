import AppKit
import SwiftUI

struct DialWidgetView: View {
    @ObservedObject var timerStore: TimerStore

    @State private var isDialDragging = false
    @State private var ringDragActivated = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = DialMetrics(size: proxy.size)

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = timerStore.status == .running ? 0.94 + (sin(t * 2.6) * 0.06) : 0.96
                let shimmer = CGFloat((sin(t * 0.7) + 1) * 0.5)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.07),
                                    timerAccentColor.opacity(0.04),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: metrics.minSide * 0.48
                            )
                        )

                    Circle()
                        .stroke(.white.opacity(0.05), lineWidth: metrics.trackWidth)

                    Circle()
                        .trim(from: 0, to: min(max(timerStore.dialFraction, 0.02), 1))
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.12),
                                    timerAccentColor.opacity(0.55),
                                    .clear
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: metrics.trackWidth + 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 10)
                        .opacity(timerStore.dialFraction > 0 ? 0.7 : 0)

                    RingSegmentsView(
                        fraction: timerStore.dialFraction,
                        segmentCount: 40,
                        radius: metrics.ringRadius,
                        segmentSize: CGSize(width: metrics.segmentWidth, height: metrics.segmentHeight),
                        activeGlow: timerStore.status == .running
                    )

                    PointerView(
                        radius: metrics.pointerRadius,
                        angle: Angle.degrees(timerStore.dialFraction * 360),
                        color: timerAccentColor,
                        pulse: pulse
                    )

                    InnerIslandOrb(color: timerAccentColor, pulse: pulse)
                        .frame(width: metrics.minSide * 0.50, height: metrics.minSide * 0.50)
                        .offset(y: -metrics.minSide * 0.03)

                    VStack(spacing: 10) {
                        Text(timerStatusText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.05))
                            )

                        VStack(spacing: 4) {
                            Text(timerStore.displayTime)
                                .font(.system(size: metrics.timeFontSize, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.7)

                            Text(timerStore.subtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.54))
                                .multilineTextAlignment(.center)
                                .frame(width: metrics.minSide * 0.52)
                        }

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [timerAccentColor.opacity(0.9), .white.opacity(0.75)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: metrics.minSide * 0.18, height: 7)
                            .shadow(color: timerAccentColor.opacity(0.35), radius: 8)
                            .overlay(alignment: .leading) {
                                Circle()
                                    .fill(.white.opacity(0.75))
                                    .frame(width: 6, height: 6)
                                    .offset(x: shimmer * (metrics.minSide * 0.18 - 6))
                            }
                    }
                }
                .contentShape(Rectangle())
                .gesture(dialGesture(metrics: metrics))
            }
        }
    }

    private var timerAccentColor: Color {
        let progress = timerStore.dialFraction
        if progress > 0.66 {
            return Color(red: 0.46, green: 0.90, blue: 0.53)
        }
        if progress > 0.33 {
            return Color(red: 0.98, green: 0.82, blue: 0.36)
        }
        return Color(red: 1.0, green: 0.52, blue: 0.37)
    }

    private var timerStatusText: String {
        switch timerStore.status {
        case .idle:
            return "Ready"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }

    private func dialGesture(metrics: DialMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard timerStore.status != .running else { return }

                let startPoint = CGPoint(x: value.startLocation.x, y: value.startLocation.y)
                let currentPoint = CGPoint(x: value.location.x, y: value.location.y)

                if ringDragActivated || metrics.isPointInRing(startPoint) {
                    ringDragActivated = true
                    isDialDragging = true
                    timerStore.setDuration(using: metrics.fraction(for: currentPoint))
                }
            }
            .onEnded { value in
                defer {
                    isDialDragging = false
                    ringDragActivated = false
                }

                let endPoint = CGPoint(x: value.location.x, y: value.location.y)

                if isDialDragging {
                    return
                }

                if metrics.isPointInCore(endPoint) {
                    timerStore.togglePrimaryAction()
                }
            }
    }
}

private struct DialMetrics {
    let size: CGSize

    var minSide: CGFloat { min(size.width, size.height) }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var ringRadius: CGFloat { minSide * 0.365 }
    var pointerRadius: CGFloat { ringRadius + (minSide * 0.01) }
    var trackWidth: CGFloat { minSide * 0.105 }
    var segmentWidth: CGFloat { minSide * 0.035 }
    var segmentHeight: CGFloat { minSide * 0.112 }
    var ringTouchMin: CGFloat { ringRadius - (trackWidth * 0.78) }
    var ringTouchMax: CGFloat { ringRadius + (trackWidth * 0.84) }
    var coreRadius: CGFloat { ringRadius - (trackWidth * 0.95) }
    var timeFontSize: CGFloat { minSide * 0.21 }

    func isPointInRing(_ point: CGPoint) -> Bool {
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance >= ringTouchMin && distance <= ringTouchMax
    }

    func isPointInCore(_ point: CGPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= coreRadius
    }

    func fraction(for point: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx) + (.pi / 2)
        if angle < 0 {
            angle += (.pi * 2)
        }
        return min(max(Double(angle / (.pi * 2)), 0), 1)
    }
}

private struct RingSegmentsView: View {
    let fraction: Double
    let segmentCount: Int
    let radius: CGFloat
    let segmentSize: CGSize
    let activeGlow: Bool

    var body: some View {
        ZStack {
            ForEach(0 ..< segmentCount, id: \.self) { index in
                let segmentFraction = (Double(index) + 1) / Double(segmentCount)
                let isActive = fraction > 0 && Double(index) < (fraction * Double(segmentCount))
                let color = segmentColor(at: segmentFraction)

                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: segmentSize.width, height: segmentSize.height)
                    .opacity(isActive ? 1.0 : 0.13)
                    .shadow(color: isActive && activeGlow ? color.opacity(0.30) : .clear, radius: 8)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((360 / Double(segmentCount)) * Double(index)))
            }
        }
    }

    private func segmentColor(at fraction: Double) -> Color {
        let stops: [(Double, Color)] = [
            (0.0, Color(red: 0.46, green: 0.90, blue: 0.53)),
            (0.40, Color(red: 0.98, green: 0.84, blue: 0.36)),
            (0.72, Color(red: 1.0, green: 0.62, blue: 0.28)),
            (1.0, Color(red: 1.0, green: 0.45, blue: 0.35))
        ]

        guard let upperIndex = stops.firstIndex(where: { fraction <= $0.0 }) else {
            return stops.last?.1 ?? .white
        }

        if upperIndex == 0 {
            return stops[0].1
        }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let amount = (fraction - lower.0) / (upper.0 - lower.0)
        return lower.1.mix(with: upper.1, amount: amount)
    }
}

private struct PointerView: View {
    let radius: CGFloat
    let angle: Angle
    let color: Color
    let pulse: Double

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(color.opacity(0.92))
                .frame(width: 12, height: 34)
                .offset(y: -(radius - 14))
                .shadow(color: color.opacity(0.32), radius: 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, color],
                        center: .center,
                        startRadius: 1,
                        endRadius: 11
                    )
                )
                .frame(width: 18, height: 18)
                .scaleEffect(pulse)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }
                .offset(y: -radius)
                .shadow(color: color.opacity(0.46), radius: 12)
        }
        .rotationEffect(angle)
    }
}

private struct InnerIslandOrb: View {
    let color: Color
    let pulse: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.08),
                            .white.opacity(0.03),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )

            Circle()
                .fill(Color.black.opacity(0.84))
                .frame(width: 84, height: 84)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.78), color.opacity(0.92), color.opacity(0.16)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 26
                    )
                )
                .frame(width: 28, height: 28)
                .scaleEffect(pulse)
                .shadow(color: color.opacity(0.46), radius: 18)
        }
    }
}

private extension Color {
    func mix(with color: Color, amount: Double) -> Color {
        let lhs = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        let rhs = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let clamped = min(max(amount, 0), 1)

        return Color(
            red: lhs.redComponent + ((rhs.redComponent - lhs.redComponent) * clamped),
            green: lhs.greenComponent + ((rhs.greenComponent - lhs.greenComponent) * clamped),
            blue: lhs.blueComponent + ((rhs.blueComponent - lhs.blueComponent) * clamped)
        )
    }
}
