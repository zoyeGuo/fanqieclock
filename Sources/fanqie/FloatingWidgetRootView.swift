import AppKit
import SwiftUI

struct FloatingWidgetRootView: View {
    @ObservedObject var timerStore: TimerStore
    @ObservedObject var settings: AppSettings
    let onTestReminder: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let contentSize = WidgetLayout.contentSize(
            scale: settings.widgetScale,
            showDragHandle: settings.showDragHandle
        )
        let dialSize = WidgetLayout.baseDialSize * settings.widgetScale

        ZStack {
            Color.clear

            VStack(spacing: 6) {
                if settings.showDragHandle {
                    DragWindowHandle()
                        .frame(width: 120 * settings.widgetScale, height: 24 * settings.widgetScale)
                        .padding(.top, 6 * settings.widgetScale)
                        .opacity(0.9)
                }

                DialWidgetView(timerStore: timerStore)
                    .frame(width: dialSize, height: dialSize)
                    .contextMenu {
                        Button("15 分钟") { timerStore.setPreset(minutes: 15) }
                        Button("25 分钟") { timerStore.setPreset(minutes: 25) }
                        Button("30 分钟") { timerStore.setPreset(minutes: 30) }
                        Button("45 分钟") { timerStore.setPreset(minutes: 45) }
                        Divider()
                        Button("设置…") { onOpenSettings() }
                        Divider()
                        Button("测试强提醒") { onTestReminder() }
                        Divider()
                        Button("重置") { timerStore.reset() }
                    }
            }
            .padding(.vertical, 8)
            .frame(width: contentSize.width, height: contentSize.height)
        }
    }
}

private struct DragWindowHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

private final class DragHandleNSView: NSView {
    private let indicatorLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        indicatorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        indicatorLayer.cornerRadius = 3
        layer?.addSublayer(indicatorLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 24)
    }

    override func layout() {
        super.layout()
        indicatorLayer.frame = NSRect(
            x: (bounds.width - 52) / 2,
            y: (bounds.height - 6) / 2,
            width: 52,
            height: 6
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
