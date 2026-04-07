import AppKit
import SwiftUI

struct WindowDragResult {
    let didMove: Bool
    let finalFrame: CGRect?
}

struct FloatingWidgetRootView: View {
    @ObservedObject var timerStore: TimerStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var todayTasksStore: TodayTasksStore
    let onTestReminder: () -> Void
    let onOpenTasks: () -> Void
    let onOpenSettings: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onWindowDragFinished: (WindowDragResult) -> Void

    var body: some View {
        let contentSize = WidgetLayout.contentSize(
            scale: settings.widgetScale,
            showDragHandle: settings.showDragHandle
        )
        let dialSize = WidgetLayout.baseDialSize * settings.widgetScale

        VStack(spacing: settings.showDragHandle ? (4 * settings.widgetScale) : 0) {
            if settings.showDragHandle {
                DragWindowHandle(onDragCompleted: onWindowDragFinished)
                    .frame(width: 112 * settings.widgetScale, height: 20 * settings.widgetScale)
                    .padding(.top, 4 * settings.widgetScale)
                    .opacity(0.86)
            }

            DialWidgetView(timerStore: timerStore)
                .frame(width: dialSize, height: dialSize)
                .contextMenu {
                    Button("15 分钟") { timerStore.setPreset(minutes: 15) }
                    Button("25 分钟") { timerStore.setPreset(minutes: 25) }
                    Button("30 分钟") { timerStore.setPreset(minutes: 30) }
                    Button("45 分钟") { timerStore.setPreset(minutes: 45) }
                    Divider()
                    Button("今日任务…") { onOpenTasks() }
                    Divider()
                    Button("设置…") { onOpenSettings() }
                    Divider()
                    Button("测试强提醒") { onTestReminder() }
                    Divider()
                    Button("重置") { timerStore.reset() }
                }

            if let task = todayTasksStore.primaryTask {
                TaskBubbleView(
                    task: task,
                    tailEdge: .top,
                    isCompleting: todayTasksStore.isCompleting(taskID: task.id),
                    onComplete: {
                        todayTasksStore.completeTask(taskID: task.id)
                    }
                )
                    .frame(width: min(contentSize.width * 0.92, 236))
                    .padding(.top, -40 * settings.widgetScale)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .top)
        .background(Color.clear)
        .onHover(perform: onHoverChanged)
    }
}

private struct DragWindowHandle: NSViewRepresentable {
    let onDragCompleted: (WindowDragResult) -> Void

    func makeNSView(context: Context) -> DragHandleNSView {
        let view = DragHandleNSView()
        view.onDragCompleted = onDragCompleted
        return view
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.onDragCompleted = onDragCompleted
    }
}

private final class DragHandleNSView: NSView {
    private let indicatorLayer = CALayer()
    var onDragCompleted: (WindowDragResult) -> Void = { _ in }
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var hasDraggedWindow = false

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
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        hasDraggedWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let dragStartMouseLocation,
            let dragStartWindowOrigin,
            let window
        else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - dragStartMouseLocation.x
        let deltaY = currentMouseLocation.y - dragStartMouseLocation.y
        let movedDistance = hypot(deltaX, deltaY)

        if movedDistance >= 2 {
            hasDraggedWindow = true
        }

        let newOrigin = NSPoint(
            x: dragStartWindowOrigin.x + deltaX,
            y: dragStartWindowOrigin.y + deltaY
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        onDragCompleted(
            WindowDragResult(
                didMove: hasDraggedWindow,
                finalFrame: window?.frame
            )
        )

        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        hasDraggedWindow = false
    }
}
