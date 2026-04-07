import AppKit
import Combine
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

private final class EdgePeekPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum DockSide {
    case left
    case right

    var revealSymbolName: String {
        switch self {
        case .left:
            return "chevron.right"
        case .right:
            return "chevron.left"
        }
    }
}

private struct EdgePeekTabView: View {
    let side: DockSide
    let onHoverChanged: (Bool) -> Void
    let onActivate: () -> Void

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.09, blue: 0.16).opacity(0.96),
                            Color(red: 0.08, green: 0.18, blue: 0.30).opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.cyan.opacity(0.22), radius: 12)
                .shadow(color: .black.opacity(0.30), radius: 14, y: 8)

            VStack(spacing: 10) {
                Image(systemName: side.revealSymbolName)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)

                Circle()
                    .fill(Color.cyan.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .shadow(color: .cyan.opacity(0.8), radius: 8)
            }
        }
        .frame(width: 34, height: 120)
        .contentShape(Rectangle())
        .onHover { isHovering in
            onHoverChanged(isHovering)
        }
        .onTapGesture {
            onActivate()
        }
    }
}

@MainActor
final class FloatingPanelController: NSWindowController {
    let panel: FloatingPanel

    private let settings: AppSettings
    private let minimumPanelEdgeSnapThreshold: CGFloat = 170
    private let expandedEdgeInset: CGFloat = 16
    private let hiddenEdgeOffset: CGFloat = 14
    private let peekPanelSize = CGSize(width: 34, height: 120)
    private let peekVisibleInset: CGFloat = 8
    private let peekHoverRevealDelay: TimeInterval = 0.18

    private var hasPlacedWindow = false
    private var cancellables = Set<AnyCancellable>()
    private var peekPanel: EdgePeekPanel?
    private var dockSide: DockSide?
    private var collapseWorkItem: DispatchWorkItem?
    private var peekRevealWorkItem: DispatchWorkItem?
    private var suppressedHoverRevealUntil = Date.distantPast

    init(
        timerStore: TimerStore,
        todayTasksStore: TodayTasksStore,
        settings: AppSettings,
        onTestReminder: @escaping () -> Void,
        onOpenTasks: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settings = settings
        let rootView = FloatingWidgetRootView(
            timerStore: timerStore,
            settings: settings,
            todayTasksStore: todayTasksStore,
            onTestReminder: onTestReminder,
            onOpenTasks: onOpenTasks,
            onOpenSettings: onOpenSettings,
            onHoverChanged: { _ in },
            onWindowDragFinished: { _ in }
        )
        let hostingView = TransparentHostingView(rootView: rootView)
        let initialSize = WidgetLayout.panelSize(
            scale: settings.widgetScale,
            showDragHandle: settings.showDragHandle
        )

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
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
        let contentContainer = Self.makeTransparentContainer(size: initialSize, child: hostingView)
        panel.contentView = contentContainer

        super.init(window: panel)

        hostingView.rootView = FloatingWidgetRootView(
            timerStore: timerStore,
            settings: settings,
            todayTasksStore: todayTasksStore,
            onTestReminder: onTestReminder,
            onOpenTasks: onOpenTasks,
            onOpenSettings: onOpenSettings,
            onHoverChanged: { [weak self] isHovering in
                self?.handlePanelHoverChanged(isHovering)
            },
            onWindowDragFinished: { [weak self] result in
                self?.handleWindowDragFinished(result)
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
        cancelScheduledCollapse()
        cancelScheduledPeekReveal()

        if dockSide != nil {
            revealDockedPanel(animated: false, ignoreHoverSuppression: true)
            return
        }

        placeWindowIfNeeded()
        panel.orderFrontRegardless()
    }

    func hideWidget() {
        cancelScheduledCollapse()
        cancelScheduledPeekReveal()
        panel.orderOut(nil)
        peekPanel?.orderOut(nil)
    }

    func toggleWidgetVisibility() {
        if isWidgetPresented {
            hideWidget()
        } else {
            presentWidget()
        }
    }

    var isWidgetPresented: Bool {
        panel.isVisible || (peekPanel?.isVisible == true)
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
        let proposedY = currentFrame.origin.y + (currentFrame.height - newSize.height)

        if let side = dockSide, let screen = activeScreen() {
            let expanded = expandedFrame(for: side, size: newSize, in: screen.visibleFrame, preferredY: proposedY)
            if peekPanel?.isVisible == true {
                let hiddenOrigin = hiddenOrigin(for: side, size: newSize, in: screen.visibleFrame, preferredY: expanded.origin.y)
                panel.setFrame(NSRect(origin: hiddenOrigin, size: newSize), display: false)
                layoutPeekPanel(for: side, on: screen, referenceFrame: expanded)
            } else {
                panel.setFrame(expanded, display: true, animate: true)
            }
            return
        }

        let newOrigin = NSPoint(x: currentFrame.origin.x, y: proposedY)
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }

    private func handleWindowDragFinished(_ result: WindowDragResult) {
        cancelScheduledCollapse()

        guard result.didMove, let finalFrame = result.finalFrame else { return }
        if let side = dockSideForFrame(finalFrame) {
            dockSide = side
            collapseDockedPanel(animated: false)
        } else {
            clearDocking()
        }
    }

    private func handlePanelHoverChanged(_ isHovering: Bool) {
        guard dockSide != nil, panel.isVisible else { return }

        if isHovering {
            cancelScheduledCollapse()
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard dockSide != nil, panel.isVisible else { return }
        cancelScheduledCollapse()

        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseDockedPanel(animated: false)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func handlePeekHoverChanged(_ isHovering: Bool) {
        if isHovering {
            schedulePeekReveal()
        } else {
            cancelScheduledPeekReveal()
        }
    }

    private func schedulePeekReveal() {
        cancelScheduledPeekReveal()

        let workItem = DispatchWorkItem { [weak self] in
            self?.revealDockedPanel(animated: false, ignoreHoverSuppression: false)
        }
        peekRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + peekHoverRevealDelay, execute: workItem)
    }

    private func cancelScheduledPeekReveal() {
        peekRevealWorkItem?.cancel()
        peekRevealWorkItem = nil
    }

    private func collapseDockedPanel(animated: Bool) {
        guard let side = dockSide, let screen = activeScreen() else { return }

        cancelScheduledCollapse()
        cancelScheduledPeekReveal()

        let expanded = expandedFrame(for: side, in: screen.visibleFrame, preferredY: panel.frame.origin.y)
        let hidden = hiddenOrigin(for: side, in: screen.visibleFrame, preferredY: expanded.origin.y)

        panel.setFrame(expanded, display: true)
        layoutPeekPanel(for: side, on: screen, referenceFrame: expanded)
        peekPanel?.orderFrontRegardless()

        if animated {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().alphaValue = 0.0
            } completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.panel.alphaValue = 1.0
                    self.panel.setFrameOrigin(hidden)
                    self.panel.orderOut(nil)
                    self.suppressedHoverRevealUntil = Date().addingTimeInterval(0.18)
                }
            }
            return
        }

        panel.setFrameOrigin(hidden)
        panel.orderOut(nil)
        suppressedHoverRevealUntil = Date().addingTimeInterval(0.18)
    }

    private func revealDockedPanel(animated: Bool, ignoreHoverSuppression: Bool) {
        guard let side = dockSide, let screen = activeScreen() else { return }
        guard ignoreHoverSuppression || Date() >= suppressedHoverRevealUntil else { return }

        cancelScheduledCollapse()
        cancelScheduledPeekReveal()

        let expanded = expandedFrame(for: side, in: screen.visibleFrame, preferredY: panel.frame.origin.y)
        panel.alphaValue = 1.0
        panel.setFrame(expanded, display: true)
        panel.orderFrontRegardless()

        if panel.isVisible {
            peekPanel?.orderOut(nil)
        }
    }

    private func clearDocking() {
        dockSide = nil
        cancelScheduledCollapse()
        cancelScheduledPeekReveal()
        peekPanel?.orderOut(nil)

        if !panel.isVisible {
            placeWindowIfNeeded()
            panel.orderFrontRegardless()
        }
    }

    private func ensurePeekPanel(for side: DockSide) -> EdgePeekPanel {
        if let peekPanel {
            peekPanel.contentView = makePeekContentView(for: side)
            return peekPanel
        }

        let panel = EdgePeekPanel(
            contentRect: NSRect(origin: .zero, size: peekPanelSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = makePeekContentView(for: side)

        peekPanel = panel
        return panel
    }

    private func makePeekContentView(for side: DockSide) -> NSView {
        let hostingView = TransparentHostingView(
            rootView: EdgePeekTabView(
                side: side,
                onHoverChanged: { [weak self] isHovering in
                    self?.handlePeekHoverChanged(isHovering)
                },
                onActivate: { [weak self] in
                    self?.revealDockedPanel(animated: false, ignoreHoverSuppression: true)
                }
            )
        )
        return Self.makeTransparentContainer(size: peekPanelSize, child: hostingView)
    }

    private static func makeTransparentContainer(size: CGSize, child: NSView) -> NSView {
        let container = TransparentContainerView(frame: NSRect(origin: .zero, size: size))
        child.frame = container.bounds
        child.autoresizingMask = [.width, .height]
        container.addSubview(child)
        return container
    }

    private func layoutPeekPanel(for side: DockSide, on screen: NSScreen, referenceFrame: NSRect) {
        let peekPanel = ensurePeekPanel(for: side)
        let frame = peekFrame(for: side, in: screen.visibleFrame, referenceFrame: referenceFrame)
        peekPanel.setFrame(frame, display: true)
    }

    private func peekFrame(for side: DockSide, in visibleFrame: NSRect, referenceFrame: NSRect) -> NSRect {
        let y = clampY(
            referenceFrame.midY - (peekPanelSize.height / 2),
            height: peekPanelSize.height,
            in: visibleFrame
        )

        let x: CGFloat
        switch side {
        case .left:
            x = visibleFrame.minX + peekVisibleInset
        case .right:
            x = visibleFrame.maxX - peekPanelSize.width - peekVisibleInset
        }

        return NSRect(origin: NSPoint(x: x, y: y), size: peekPanelSize)
    }

    private func expandedFrame(
        for side: DockSide,
        size: CGSize? = nil,
        in visibleFrame: NSRect,
        preferredY: CGFloat
    ) -> NSRect {
        let panelSize = size ?? panel.frame.size
        let y = clampY(preferredY, height: panelSize.height, in: visibleFrame)

        let x: CGFloat
        switch side {
        case .left:
            x = visibleFrame.minX + expandedEdgeInset
        case .right:
            x = visibleFrame.maxX - panelSize.width - expandedEdgeInset
        }

        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }

    private func hiddenOrigin(
        for side: DockSide,
        size: CGSize? = nil,
        in visibleFrame: NSRect,
        preferredY: CGFloat
    ) -> NSPoint {
        let panelSize = size ?? panel.frame.size
        let y = clampY(preferredY, height: panelSize.height, in: visibleFrame)

        switch side {
        case .left:
            return NSPoint(x: visibleFrame.minX - panelSize.width - hiddenEdgeOffset, y: y)
        case .right:
            return NSPoint(x: visibleFrame.maxX + hiddenEdgeOffset, y: y)
        }
    }

    private func clampY(_ proposedY: CGFloat, height: CGFloat, in visibleFrame: NSRect) -> CGFloat {
        min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - height)
    }

    private func activeScreen() -> NSScreen? {
        if let peekPanel, peekPanel.isVisible, let screen = screenContaining(peekPanel.frame) {
            return screen
        }

        return screenContaining(panel.frame) ?? panel.screen ?? NSScreen.main
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.visibleFrame.intersects(frame) || screen.frame.intersects(frame)
        }
    }

    private func dockSideForFrame(_ frame: CGRect) -> DockSide? {
        guard let screen = screenContaining(frame) ?? panel.screen ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let panelEdgeSnapThreshold = max(minimumPanelEdgeSnapThreshold, min(frame.width * 0.45, 220))

        if frame.minX <= visible.minX + panelEdgeSnapThreshold {
            return .left
        }

        if frame.maxX >= visible.maxX - panelEdgeSnapThreshold {
            return .right
        }

        return nil
    }
}
