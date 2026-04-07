import SwiftUI

struct DialWidgetView: View {
    @ObservedObject var timerStore: TimerStore

    @State private var isDialDragging = false
    @State private var ringDragActivated = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = DialMetrics(size: proxy.size)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .black.opacity(0.18),
                                .black.opacity(0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: metrics.minSide * 0.31
                        )
                    )
                    .frame(width: metrics.minSide * 0.72, height: metrics.minSide * 0.72)
                    .offset(y: 12)

                dialFace(metrics: metrics)
            }
            .contentShape(Rectangle())
            .gesture(dialGesture(metrics: metrics))
        }
    }

    private func dialFace(metrics: DialMetrics) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .black.opacity(0.58),
                            .black.opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: metrics.minSide * 0.42
                    )
                )
                .frame(width: metrics.minSide * 0.9, height: metrics.minSide * 0.9)

            RingSegmentsView(
                fraction: timerStore.dialFraction,
                segmentCount: 24,
                radius: metrics.ringRadius,
                segmentSize: CGSize(width: 11, height: 28),
                activeGlow: timerStore.status == .running
            )

            PointerView(radius: metrics.pointerRadius, angle: Angle.degrees(timerStore.dialFraction * 360))

            MechanicalCatFaceView(timerStore: timerStore)
                .offset(y: -52)

            VStack(spacing: 8) {
                Text(timerStore.displayTime)
                    .font(.system(size: 70, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

                Text(timerStore.subtitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            }
            .offset(y: 54)
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

enum BubbleTailEdge: Equatable {
    case top
    case bottom
}

struct TaskBubbleView: View {
    let task: TodoistTask
    let tailEdge: BubbleTailEdge
    let isCompleting: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tailEdge == .top {
                BubbleTail()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        BubbleTail()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.18),
                                        .white.opacity(0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        BubbleTail()
                            .stroke(.white.opacity(0.16), lineWidth: 0.9)
                    )
                    .frame(width: 14, height: 9)
                    .rotationEffect(.degrees(180))
                    .offset(x: 18, y: 1)
                    .zIndex(1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.70, green: 0.93, blue: 1.0),
                                    Color(red: 0.42, green: 0.84, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 7, height: 7)
                        .shadow(color: .cyan.opacity(0.45), radius: 6)

                    Text("今日第一件")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))

                    Spacer(minLength: 0)

                    if let dueText = task.compactDueSummary {
                        Text(dueText)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Button(action: onComplete) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 22, height: 22)

                            Circle()
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                                .frame(width: 22, height: 22)

                            if isCompleting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.green)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.green.opacity(0.88))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCompleting)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.content)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(isCompleting ? "正在同步完成…" : "点击圆圈完成")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.09))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.22),
                                    .white.opacity(0.08),
                                    .white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.12, blue: 0.17).opacity(0.22),
                                    Color(red: 0.05, green: 0.07, blue: 0.10).opacity(0.10)
                                ],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.9)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.10), lineWidth: 2)
                        .blur(radius: 6)
                }
                .overlay(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 42, height: 4)
                        .blur(radius: 3)
                        .offset(x: 14, y: 8)
                }
            )

            if tailEdge == .bottom {
                BubbleTail()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        BubbleTail()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.18),
                                        .white.opacity(0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        BubbleTail()
                            .stroke(.white.opacity(0.16), lineWidth: 0.9)
                    )
                    .frame(width: 14, height: 9)
                    .offset(x: 16, y: -1)
            }
        }
        .shadow(color: .white.opacity(0.05), radius: 12)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
        .opacity(isCompleting ? 0.88 : 1.0)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY * 0.72)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.maxY * 0.56)
        )
        path.closeSubpath()
        return path
    }
}

private struct DialMetrics {
    let size: CGSize

    var minSide: CGFloat { min(size.width, size.height) }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var outerCornerRadius: CGFloat { minSide * 0.1 }
    var screenCornerRadius: CGFloat { minSide * 0.11 }
    var screenSize: CGFloat { minSide * 0.78 }
    var ringRadius: CGFloat { minSide * 0.36 }
    var pointerRadius: CGFloat { ringRadius + 10 }
    var ringTouchMin: CGFloat { ringRadius - 18 }
    var ringTouchMax: CGFloat { ringRadius + 22 }
    var coreRadius: CGFloat { ringRadius * 0.44 }

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
                let active = fraction > 0 && Double(index) < (fraction * Double(segmentCount))

                Capsule(style: .continuous)
                    .fill(segmentColor(at: segmentFraction))
                    .frame(width: segmentSize.width, height: segmentSize.height)
                    .opacity(active ? 1 : 0.18)
                    .shadow(
                        color: active && activeGlow ? segmentColor(at: segmentFraction).opacity(0.45) : .clear,
                        radius: 8
                    )
                    .offset(y: -radius)
                    .rotationEffect(.degrees((360 / Double(segmentCount)) * Double(index)))
            }
        }
    }

    private func segmentColor(at fraction: Double) -> Color {
        let stops: [(Double, Color)] = [
            (0.0, Color(red: 0.46, green: 0.88, blue: 0.55)),
            (0.35, Color(red: 0.96, green: 0.84, blue: 0.35)),
            (0.65, Color(red: 1.0, green: 0.62, blue: 0.26)),
            (1.0, Color(red: 1.0, green: 0.36, blue: 0.34))
        ]

        guard let upperIndex = stops.firstIndex(where: { fraction <= $0.0 }) else {
            return stops.last!.1
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

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(red: 0.35, green: 0.84, blue: 1.0))
                .frame(width: 11, height: 34)
                .offset(y: -(radius - 14))
                .shadow(color: Color.cyan.opacity(0.45), radius: 10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(red: 0.45, green: 0.86, blue: 1.0)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 10
                    )
                )
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.7), lineWidth: 1)
                }
                .offset(y: -radius)
                .shadow(color: Color.cyan.opacity(0.55), radius: 12)
        }
        .rotationEffect(angle)
    }
}

private struct MechanicalCatFaceView: View {
    @ObservedObject var timerStore: TimerStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = timerStore.status == .running ? sin(t * 1.8) * 2.2 : sin(t * 0.8) * 0.8
            let pulse = 0.92 + (sin(t * 2.3) * 0.05 * timerStore.centerGlowStrength)
            let eyeHeight = timerStore.status == .paused ? 4.0 : 12.0
            let eyeColor = eyeColor(for: timerStore.eyeColorProgress)

            ZStack {
                Triangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -15, y: -15)

                Triangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(10))
                    .offset(x: 15, y: -15)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 0.42, green: 0.50, blue: 0.57)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.18, blue: 0.24),
                                Color(red: 0.05, green: 0.07, blue: 0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 33, height: 33)

                HStack(spacing: 9) {
                    Capsule(style: .continuous)
                        .fill(eyeColor)
                        .frame(width: 5, height: eyeHeight)

                    Capsule(style: .continuous)
                        .fill(eyeColor)
                        .frame(width: 5, height: eyeHeight)
                }
                .shadow(color: eyeColor.opacity(0.55), radius: 6)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                eyeColor,
                                eyeColor.opacity(0.15)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse)
                    .offset(y: 11)
                    .shadow(color: eyeColor.opacity(0.5), radius: 12)
            }
            .offset(y: bob - 6)
        }
    }

    private func eyeColor(for fraction: Double) -> Color {
        let green = Color(red: 0.47, green: 0.88, blue: 0.56)
        let yellow = Color(red: 0.97, green: 0.80, blue: 0.32)
        let red = Color(red: 1.0, green: 0.39, blue: 0.36)

        if fraction < 0.35 {
            return green.mix(with: yellow, amount: fraction / 0.35)
        }

        let upperAmount = (fraction - 0.35) / 0.65
        return yellow.mix(with: red, amount: upperAmount)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
