import AppKit
import Combine
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSWindowController {
    let panel: FloatingPanel
    private let settings: AppSettings
    private var hasPlacedWindow = false
    private var cancellables = Set<AnyCancellable>()

    init(
        timerStore: TimerStore,
        settings: AppSettings,
        onTestReminder: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settings = settings
        let rootView = FloatingWidgetRootView(
            timerStore: timerStore,
            settings: settings,
            onTestReminder: onTestReminder,
            onOpenSettings: onOpenSettings
        )
        let hostingView = NSHostingView(rootView: rootView)
        let initialSize = WidgetLayout.panelSize(
            scale: settings.widgetScale,
            showDragHandle: settings.showDragHandle
        )

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = hostingView

        super.init(window: panel)
        bindSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        placeWindowIfNeeded()
    }

    private func placeWindowIfNeeded() {
        guard !hasPlacedWindow, let screen = NSScreen.main else { return }

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - panel.frame.width - 28,
            y: visible.midY - (panel.frame.height / 2)
        )

        panel.setFrameOrigin(origin)
        hasPlacedWindow = true
    }

    private func bindSettings() {
        settings.$widgetScale
            .combineLatest(settings.$showDragHandle)
            .sink { [weak self] _, _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)
    }

    private func updatePanelSize() {
        let newSize = WidgetLayout.panelSize(
            scale: settings.widgetScale,
            showDragHandle: settings.showDragHandle
        )

        let currentFrame = panel.frame
        let newOrigin = NSPoint(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + (currentFrame.height - newSize.height)
        )

        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }
}
