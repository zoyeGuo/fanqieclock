import AppKit
import Combine
import QuartzCore
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init(rootView: Content, sizingOptions: NSHostingSizingOptions) {
        fatalError("init(rootView:sizingOptions:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TransparentContainerView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
    }
}

@MainActor
final class FloatingPanelController: NSWindowController {
    let panel: FloatingPanel

    private let settings: AppSettings
    private let screenID: NSNumber
    private let metricsStore = IslandMetricsStore()
    private var hasPlacedWindow = false
    private var isExpanded = false
    private var cancellables = Set<AnyCancellable>()

    init(
        screenID: NSNumber,
        timerStore: TimerStore,
        todayTasksStore: TodayTasksStore,
        focusStatsStore: FocusStatsStore,
        settings: AppSettings,
        onTestReminder: @escaping () -> Void,
        onOpenTasks: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.screenID = screenID
        self.settings = settings

        metricsStore.update(from: Self.resolveScreen(for: screenID) ?? NSScreen.main)
        let initialSize = WidgetLayout.panelSize(
            scale: settings.widgetScale,
            isExpanded: false,
            notchMetrics: metricsStore.notchMetrics
        )
        let rootView = FloatingWidgetRootView(
            timerStore: timerStore,
            settings: settings,
            todayTasksStore: todayTasksStore,
            focusStatsStore: focusStatsStore,
            metricsStore: metricsStore,
            onTestReminder: onTestReminder,
            onOpenTasks: onOpenTasks,
            onOpenSettings: onOpenSettings,
            onExpansionChanged: { _ in }
        )
        let hostingView = TransparentHostingView(rootView: rootView)

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
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

        let contentContainer = Self.makeTransparentContainer(size: initialSize, child: hostingView)
        panel.contentView = contentContainer

        super.init(window: panel)

        hostingView.rootView = FloatingWidgetRootView(
            timerStore: timerStore,
            settings: settings,
            todayTasksStore: todayTasksStore,
            focusStatsStore: focusStatsStore,
            metricsStore: metricsStore,
            onTestReminder: onTestReminder,
            onOpenTasks: onOpenTasks,
            onOpenSettings: onOpenSettings,
            onExpansionChanged: { [weak self] expanded in
                self?.setExpanded(expanded, animated: true)
            }
        )

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

    func presentWidget() {
        placeWindowIfNeeded()
        panel.orderFrontRegardless()
        refreshMetricsAndLayout(animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.refreshMetricsAndLayout(animated: false)
        }
    }

    func hideWidget() {
        panel.orderOut(nil)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func dispose() {
        panel.orderOut(nil)
        close()
    }

    func toggleWidgetVisibility() {
        if panel.isVisible {
            hideWidget()
        } else {
            presentWidget()
        }
    }

    private func bindSettings() {
        settings.$widgetScale
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePanelFrame(animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: panel)
            .sink { [weak self] _ in
                self?.refreshMetricsAndLayout(animated: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.refreshMetricsAndLayout(animated: false)
            }
            .store(in: &cancellables)
    }

    private func placeWindowIfNeeded() {
        guard !hasPlacedWindow else {
            updatePanelFrame(animated: false)
            return
        }

        metricsStore.update(from: activeScreen())
        let frame = anchoredFrame(for: panelSize)
        panel.setFrame(frame, display: false)
        hasPlacedWindow = true
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        updatePanelFrame(animated: animated)
    }

    private func updatePanelFrame(animated: Bool) {
        guard hasPlacedWindow else { return }
        metricsStore.update(from: activeScreen())
        let frame = anchoredFrame(for: panelSize)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = isExpanded ? 0.18 : 0.14
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.22, 1.0)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private var panelSize: CGSize {
        WidgetLayout.panelSize(
            scale: settings.widgetScale,
            isExpanded: isExpanded,
            notchMetrics: metricsStore.notchMetrics
        )
    }

    private func anchoredFrame(for size: CGSize) -> NSRect {
        let screen = activeScreen()
        let screenFrame = screen.frame

        let x = screenFrame.midX - (size.width / 2)
        let topOverlap: CGFloat = metricsStore.notchMetrics.hasNotch ? 3 : 1
        let y = screenFrame.maxY - size.height + topOverlap

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func activeScreen() -> NSScreen {
        if let resolved = Self.resolveScreen(for: screenID) {
            return resolved
        }

        if let screen = panel.screen {
            return screen
        }

        if let main = NSScreen.main {
            return main
        }

        guard let first = NSScreen.screens.first else {
            fatalError("No available screens to place the floating panel.")
        }
        return first
    }

    private static func resolveScreen(for screenID: NSNumber) -> NSScreen? {
        NSScreen.screens.first(where: { $0.displayID == screenID })
    }

    private static func makeTransparentContainer(size: CGSize, child: NSView) -> NSView {
        let container = TransparentContainerView(frame: NSRect(origin: .zero, size: size))
        child.frame = container.bounds
        child.autoresizingMask = [.width, .height]
        container.addSubview(child)
        return container
    }

    private func refreshMetricsAndLayout(animated: Bool) {
        let screen = activeScreen()
        metricsStore.update(from: screen)
        if hasPlacedWindow {
            updatePanelFrame(animated: animated)
        }
    }
}
