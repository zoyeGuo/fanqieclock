import SwiftUI

struct FloatingWidgetRootView: View {
    @ObservedObject var timerStore: TimerStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var todayTasksStore: TodayTasksStore
    @ObservedObject var focusStatsStore: FocusStatsStore
    @ObservedObject var metricsStore: IslandMetricsStore

    let onTestReminder: () -> Void
    let onOpenTasks: () -> Void
    let onOpenSettings: () -> Void
    let onExpansionChanged: (Bool) -> Void

    @State private var isExpanded = false
    @State private var revealExpandedContent = false
    @State private var isExpandedHovered = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var pendingOpenTask: Task<Void, Never>?

    var body: some View {
        let notchMetrics = metricsStore.notchMetrics
        let panelSize = WidgetLayout.panelSize(
            scale: settings.widgetScale,
            isExpanded: isExpanded,
            notchMetrics: notchMetrics
        )

        ZStack(alignment: .top) {
            SingleBlackIslandShell(
                isExpanded: isExpanded,
                hasNotch: notchMetrics.hasNotch
            )
                .frame(width: panelSize.width, height: panelSize.height)

            if isExpanded {
                expandedContent
                    .opacity(revealExpandedContent ? 1 : 0)
                    .scaleEffect(revealExpandedContent ? 1 : 0.992, anchor: .top)
                    .offset(y: revealExpandedContent ? 0 : -8)
                    .transition(.identity)
            } else {
                compactContent
                    .transition(.opacity)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
        .background(Color.clear)
        .contentShape(TopAttachedBar(radius: isExpanded ? 22 : (notchMetrics.hasNotch ? 14 : 18)))
        .animation(.snappy(duration: 0.18, extraBounce: 0.01), value: isExpanded)
        .animation(.easeOut(duration: 0.12), value: revealExpandedContent)
        .contextMenu {
            Button("15 分钟") { timerStore.setPreset(minutes: 15) }
            Button("25 分钟") { timerStore.setPreset(minutes: 25) }
            Button("45 分钟") { timerStore.setPreset(minutes: 45) }
            Divider()
            Button("今日任务…") { onOpenTasks() }
            Button("刷新今日任务") { todayTasksStore.refresh() }
            Divider()
            Button("设置…") { onOpenSettings() }
            Button("测试强提醒") { onTestReminder() }
            Divider()
            Button("重置") { timerStore.reset() }
        }
        .onAppear {
            onExpansionChanged(isExpanded)
            if todayTasksStore.hasConfiguredToken, todayTasksStore.state == .idle {
                todayTasksStore.refresh()
            }
        }
        .onDisappear {
            cancelCollapse()
            cancelPendingOpen()
        }
        .onChange(of: isExpanded) { _, newValue in
            onExpansionChanged(newValue)
        }
        .onHover { hovering in
            if isExpanded {
                isExpandedHovered = hovering
                if hovering {
                    cancelCollapse()
                    if !revealExpandedContent {
                        withAnimation(.easeOut(duration: 0.10)) {
                            revealExpandedContent = true
                        }
                    }
                } else {
                    scheduleCollapse()
                }
            } else if hovering, metricsStore.notchMetrics.hasNotch {
                queueOpenIsland()
            } else {
                isExpandedHovered = false
                cancelPendingOpen()
            }
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        if metricsStore.notchMetrics.hasNotch {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    openIsland()
                }
        } else {
            Button {
                openIsland()
            } label: {
                HStack(spacing: 10) {
                    StatusDot(color: timerAccentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)

                        Text(compactTaskSummary)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(timerStore.displayTime)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(
                    width: WidgetLayout.compactBaseSize(for: metricsStore.notchMetrics).width * settings.widgetScale
                )
                .frame(
                    height: WidgetLayout.compactBaseSize(for: metricsStore.notchMetrics).height * settings.widgetScale,
                    alignment: .top
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var expandedContent: some View {
        let notchMetrics = metricsStore.notchMetrics
        let scale = settings.widgetScale
        let cardHeight = WidgetLayout.moduleCardHeight(for: notchMetrics, scale: scale)
        let taskViewportHeight = WidgetLayout.taskViewportHeight(for: notchMetrics, scale: scale)
        let taskContentScale = WidgetLayout.taskContentScale(for: notchMetrics, scale: scale)
        let statsContentScale = WidgetLayout.statsContentScale(for: notchMetrics, scale: scale)

        return VStack(spacing: 8 * scale) {
            HStack(spacing: 10) {
                Text("Fanqie X")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.06))
                    )

                Text(compactTaskCountText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                Spacer(minLength: 0)

                SmallIconButton(symbol: "arrow.clockwise") {
                    todayTasksStore.refresh()
                }
                SmallIconButton(symbol: "gearshape.fill") {
                    onOpenSettings()
                }
                SmallIconButton(symbol: "xmark") {
                    closeIsland(force: true)
                }
            }
            .opacity(revealExpandedContent ? 1 : 0)
            .offset(y: revealExpandedContent ? 0 : -8)

            HStack(alignment: .top, spacing: 12 * scale) {
                leftSummary(cardHeight: cardHeight, taskViewportHeight: taskViewportHeight, contentScale: taskContentScale)
                    .frame(
                        width: WidgetLayout.overviewModuleWidth(for: notchMetrics, scale: scale),
                        height: cardHeight,
                        alignment: .top
                    )
                    .opacity(revealExpandedContent ? 1 : 0)
                    .offset(y: revealExpandedContent ? 0 : 10)

                statsPane(cardHeight: cardHeight, contentScale: statsContentScale)
                    .frame(
                        width: WidgetLayout.statsModuleWidth(for: notchMetrics, scale: scale),
                        height: cardHeight,
                        alignment: .top
                    )
                    .opacity(revealExpandedContent ? 1 : 0)
                    .offset(y: revealExpandedContent ? 0 : 12)

                focusPane(cardHeight: cardHeight)
                    .frame(
                        width: WidgetLayout.focusModuleWidth(for: notchMetrics, scale: scale),
                        height: cardHeight,
                        alignment: .top
                    )
                    .opacity(revealExpandedContent ? 1 : 0)
                    .offset(y: revealExpandedContent ? 0 : 14)
            }
        }
        .padding(.horizontal, 16 * scale)
        .padding(.top, 12 * scale)
        .padding(.bottom, 6 * scale)
        .frame(
            width: WidgetLayout.expandedBaseSize(for: notchMetrics).width * scale
        )
        .frame(
            height: WidgetLayout.expandedBaseSize(for: notchMetrics).height * scale,
            alignment: .top
        )
    }

    private func leftSummary(cardHeight: CGFloat, taskViewportHeight: CGFloat, contentScale: CGFloat) -> some View {
        IslandPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DateBadgeView()
                    Spacer(minLength: 0)
                    Text(compactTaskCountText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                }

                Text("今日任务")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text(overviewStatusLine)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                if todayTasksStore.state == .loaded {
                    TaskScrollColumn(
                        tasks: todayTasksStore.orderedTasks,
                        primaryTaskID: todayTasksStore.primaryTask?.id,
                        visualScale: contentScale,
                        isCompleting: { taskID in
                            todayTasksStore.isCompleting(taskID: taskID)
                        },
                        onComplete: { taskID in
                            todayTasksStore.completeTask(taskID: taskID)
                        }
                    )
                    .frame(maxHeight: taskViewportHeight)
                } else {
                    compactTaskState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func statsPane(cardHeight: CGFloat, contentScale: CGFloat) -> some View {
        IslandPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("专注统计")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                    Spacer(minLength: 0)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.82))
                }

                VStack(spacing: 8) {
                    FocusMetricTile(
                        icon: "sun.max.fill",
                        tint: Color(red: 1.0, green: 0.76, blue: 0.30),
                        title: "今日时长",
                        value: focusStatsStore.formattedDuration(for: focusStatsStore.todaySummary),
                        subtitle: "\(focusStatsStore.todaySummary.sessionCount) 轮",
                        visualScale: contentScale
                    )

                    FocusMetricTile(
                        icon: "calendar.badge.clock",
                        tint: Color(red: 0.42, green: 0.82, blue: 1.0),
                        title: "本周时长",
                        value: focusStatsStore.formattedDuration(for: focusStatsStore.weekSummary),
                        subtitle: "\(focusStatsStore.weekSummary.sessionCount) 轮",
                        visualScale: contentScale
                    )

                    FocusMetricTile(
                        icon: "flame.fill",
                        tint: Color(red: 1.0, green: 0.48, blue: 0.34),
                        title: "专注节奏",
                        value: focusPaceText,
                        subtitle: "最近 7 天",
                        visualScale: contentScale
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var compactTaskState: some View {
        Group {
            switch todayTasksStore.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("同步今日任务中…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }
            case .missingToken:
                Text("未连接 Todoist")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            case let .failed(message):
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(3)
            case .empty:
                Text("今天的任务已经清空。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            case .loaded:
                EmptyView()
            }
        }
    }

    private func focusPane(cardHeight: CGFloat) -> some View {
        IslandPanelCard {
            VStack(spacing: 10 * settings.widgetScale) {
                DialWidgetView(timerStore: timerStore)
                    .frame(
                        width: WidgetLayout.focusModuleDialSize(for: metricsStore.notchMetrics, scale: settings.widgetScale),
                        height: WidgetLayout.focusModuleDialSize(for: metricsStore.notchMetrics, scale: settings.widgetScale)
                    )
                    .padding(.top, 10 * settings.widgetScale)

                Text("拖动外圈设定时长，点击中心开始或暂停")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var timerAccentColor: Color {
        let progress = timerStore.dialFraction
        if progress > 0.66 {
            return Color(red: 0.44, green: 0.90, blue: 0.50)
        }
        if progress > 0.33 {
            return Color(red: 0.98, green: 0.79, blue: 0.34)
        }
        return Color(red: 1.0, green: 0.47, blue: 0.34)
    }

    private var compactTitle: String {
        switch timerStore.status {
        case .idle:
            return "准备开始专注"
        case .running:
            return "正在专注"
        case .paused:
            return "已暂停"
        case .completed:
            return "本轮已完成"
        }
    }

    private var compactTaskCountText: String {
        "\(todayTasksStore.orderedTasks.count) Tasks"
    }

    private var compactTaskSummary: String {
        todayTasksStore.primaryTask?.content ?? "点击展开"
    }

    private var focusPaceText: String {
        let total = focusStatsStore.weekSummary.sessionCount
        if total >= 14 {
            return "高频"
        }
        if total >= 7 {
            return "稳定"
        }
        if total >= 1 {
            return "起步"
        }
        return "待开始"
    }

    private var overviewStatusLine: String {
        switch timerStore.status {
        case .idle:
            return "定位中… 等待开始"
        case .running:
            return "专注进行中…"
        case .paused:
            return "已暂停…"
        case .completed:
            return "本轮完成…"
        }
    }

    private func openIsland() {
        cancelPendingOpen()
        cancelCollapse()
        revealExpandedContent = false
        isExpandedHovered = true

        withAnimation(.snappy(duration: 0.18, extraBounce: 0.01)) {
            isExpanded = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard isExpanded else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                revealExpandedContent = true
            }
        }
    }

    private func closeIsland(force: Bool = false) {
        cancelCollapse()
        cancelPendingOpen()

        Task { @MainActor in
            if !force {
                try? await Task.sleep(nanoseconds: 35_000_000)
                guard !isExpandedHovered else {
                    withAnimation(.easeOut(duration: 0.10)) {
                        revealExpandedContent = true
                    }
                    return
                }
            }

            withAnimation(.easeOut(duration: 0.08)) {
                revealExpandedContent = false
            }

            try? await Task.sleep(nanoseconds: 55_000_000)
            guard force || !isExpandedHovered else { return }
            withAnimation(.snappy(duration: 0.15, extraBounce: 0)) {
                isExpanded = false
            }
        }
    }

    private func scheduleCollapse() {
        cancelCollapse()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled, isExpanded, !isExpandedHovered else { return }
            closeIsland()
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func queueOpenIsland() {
        guard !isExpanded else { return }
        cancelPendingOpen()
        pendingOpenTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 18_000_000)
            guard !Task.isCancelled, !isExpanded else { return }
            openIsland()
        }
    }

    private func cancelPendingOpen() {
        pendingOpenTask?.cancel()
        pendingOpenTask = nil
    }
}

private struct SingleBlackIslandShell: View {
    let isExpanded: Bool
    let hasNotch: Bool

    var body: some View {
        let radius: CGFloat = isExpanded ? 22 : (hasNotch ? 14 : 18)

        TopAttachedBar(radius: radius)
            .fill(Color.black)
            .overlay {
                if isExpanded || !hasNotch {
                    TopAttachedBar(radius: radius)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                }
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        .white.opacity(isExpanded ? 0.10 : 0),
                        .white.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isExpanded ? 42 : 12)
                .clipShape(TopAttachedBar(radius: radius))
            }
            .shadow(
                color: .black.opacity(isExpanded || !hasNotch ? 0.28 : 0),
                radius: isExpanded ? 16 : 3,
                y: isExpanded ? 8 : 1
            )
    }
}

private struct IslandPanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    )
            )
    }
}

private struct SmallIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: 28, height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.6), radius: 8)
    }
}

private struct CompactTaskRow: View {
    let task: TodoistTask
    let isPrimary: Bool
    let visualScale: CGFloat
    let isCompleting: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 10 * visualScale) {
            Button(action: onComplete) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 22 * visualScale, height: 22 * visualScale)

                    Circle()
                        .strokeBorder(isPrimary ? .green.opacity(0.65) : .white.opacity(0.14), lineWidth: 1)
                        .frame(width: 22 * visualScale, height: 22 * visualScale)

                    if isCompleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.green)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9 * visualScale, weight: .heavy))
                            .foregroundStyle(.green.opacity(0.86))
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.content)
                    .font(.system(size: 12 * visualScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)

                if let due = task.compactDueSummary {
                    Text(due)
                        .font(.system(size: 10 * visualScale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10 * visualScale)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isPrimary ? 0.07 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isPrimary ? .cyan.opacity(0.12) : .white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

private struct FocusMetricTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let subtitle: String
    let visualScale: CGFloat

    var body: some View {
        HStack(spacing: 10 * visualScale) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 34 * visualScale, height: 34 * visualScale)

                Image(systemName: icon)
                    .font(.system(size: 15 * visualScale, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10 * visualScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))

                Text(value)
                    .font(.system(size: 14 * visualScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10 * visualScale, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * visualScale)
        .padding(.vertical, 9 * visualScale)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct TaskScrollColumn: View {
    let tasks: [TodoistTask]
    let primaryTaskID: String?
    let visualScale: CGFloat
    let isCompleting: (String) -> Bool
    let onComplete: (String) -> Void

    @State private var viewportHeight: CGFloat = 1
    @State private var contentHeight: CGFloat = 1
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: TaskScrollOffsetPreferenceKey.self,
                                value: max(0, -proxy.frame(in: .named("task-scroll")).minY)
                            )
                    }
                    .frame(height: 0)

                    ForEach(tasks) { task in
                        CompactTaskRow(
                            task: task,
                            isPrimary: primaryTaskID == task.id,
                            visualScale: visualScale,
                            isCompleting: isCompleting(task.id),
                            onComplete: {
                                onComplete(task.id)
                            }
                        )
                    }
                }
                .padding(.trailing, 10)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: TaskScrollContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                    }
                )
            }
            .coordinateSpace(name: "task-scroll")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: TaskScrollViewportHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                }
            )
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)

                    Rectangle()
                        .fill(.black)

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)
                }
            }

            if showsCustomIndicator {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.06))
                    .frame(width: 4, height: viewportHeight - 8)
                    .overlay(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.92),
                                        Color.cyan.opacity(0.55)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 4, height: thumbHeight)
                            .shadow(color: .cyan.opacity(0.20), radius: 6)
                            .offset(y: thumbOffset)
                    }
                    .padding(.trailing, 1)
            }
        }
        .onPreferenceChange(TaskScrollViewportHeightPreferenceKey.self) { viewportHeight = $0 }
        .onPreferenceChange(TaskScrollContentHeightPreferenceKey.self) { contentHeight = $0 }
        .onPreferenceChange(TaskScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
    }

    private var showsCustomIndicator: Bool {
        contentHeight > viewportHeight + 8
    }

    private var thumbHeight: CGFloat {
        let proportionalHeight = viewportHeight * (viewportHeight / max(contentHeight, viewportHeight))
        return max(30, min(viewportHeight - 8, proportionalHeight))
    }

    private var thumbOffset: CGFloat {
        let scrollableHeight = max(contentHeight - viewportHeight, 1)
        let travel = max((viewportHeight - 8) - thumbHeight, 0)
        return min(travel, (scrollOffset / scrollableHeight) * travel)
    }
}

private struct TaskScrollViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TaskScrollContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TaskScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DateBadgeView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let components = Calendar.current.dateComponents([.weekday, .month, .day], from: context.date)
            let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let weekday = weekdaySymbols[max(0, min((components.weekday ?? 1) - 1, weekdaySymbols.count - 1))]
            let month = components.month ?? 1
            let day = components.day ?? 1

            Text("\(weekday), \(month)/\(day)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.green.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.green.opacity(0.14))
                )
        }
    }
}

private struct TopAttachedBar: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
