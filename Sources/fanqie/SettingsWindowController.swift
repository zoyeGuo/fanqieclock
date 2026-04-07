import AppKit
import SwiftUI

enum WidgetLayout {
    static let baseWidth: CGFloat = 282
    static let baseHeightWithHandle: CGFloat = 424
    static let baseHeightWithoutHandle: CGFloat = 396
    static let baseDialSize: CGFloat = 272

    static func contentSize(scale: Double, showDragHandle: Bool) -> CGSize {
        CGSize(
            width: baseWidth * scale,
            height: (showDragHandle ? baseHeightWithHandle : baseHeightWithoutHandle) * scale
        )
    }

    static func panelSize(scale: Double, showDragHandle: Bool) -> CGSize {
        contentSize(scale: scale, showDragHandle: showDragHandle)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let todayTasksStore: TodayTasksStore

    init(settings: AppSettings, todayTasksStore: TodayTasksStore) {
        self.todayTasksStore = todayTasksStore
        let rootView = SettingsRootView(settings: settings, todayTasksStore: todayTasksStore)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if todayTasksStore.hasConfiguredToken {
            todayTasksStore.refresh()
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var todayTasksStore: TodayTasksStore
    private let todoistEnvKey = TodoistClient.tokenEnvironmentKey

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.18),
                    Color(red: 0.05, green: 0.07, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text("这里控制默认时长、悬浮组件大小和提醒方式，改完会立即生效。")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    SettingsCard(title: "专注时间", subtitle: "默认时长只影响新一轮和重置后的起始时间。") {
                        HStack {
                            Text("默认专注时长")
                            Spacer()
                            Stepper(value: $settings.defaultFocusMinutes, in: 5 ... 60, step: 5) {
                                Text("\(settings.defaultFocusMinutes) 分钟")
                                    .monospacedDigit()
                            }
                            .labelsHidden()
                            Text("\(settings.defaultFocusMinutes) min")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }

                    SettingsCard(title: "外观", subtitle: "组件大小会立即同步到桌面悬浮表盘。") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("组件大小")
                                Spacer()
                                Text("\(Int((settings.widgetScale * 100).rounded()))%")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                            }

                            Slider(value: $settings.widgetScale, in: 0.8 ... 1.3, step: 0.05)
                                .tint(.cyan)

                            Toggle("显示顶部拖动条", isOn: $settings.showDragHandle)
                                .toggleStyle(.switch)
                        }
                    }

                    SettingsCard(title: "提醒", subtitle: "可以保留强提醒，也可以只留下声音。") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("启用全屏强提醒", isOn: $settings.enableStrongReminder)
                                .toggleStyle(.switch)

                            Toggle("播放提醒声音", isOn: $settings.playReminderSound)
                                .toggleStyle(.switch)
                        }
                    }

                    SettingsCard(title: "Todoist", subtitle: "今日任务会通过环境变量读取你的 Todoist Token。") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("环境变量名：\(todoistEnvKey)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.88))

                            SettingsCommandLine(
                                title: "终端运行时",
                                command: "export \(todoistEnvKey)=\"你的 Todoist Token\""
                            )

                            SettingsCommandLine(
                                title: "桌面 App 启动时",
                                command: "launchctl setenv \(todoistEnvKey) \"你的 Todoist Token\""
                            )

                            Text("设置后请完全退出并重新打开应用。")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    SettingsCard(title: "今日任务排序", subtitle: "气泡只会显示排序第一的任务，你可以在这里调整今天的专注顺序。") {
                        TodayTasksOrderingSection(store: todayTasksStore)
                    }

                    HStack {
                        Spacer()

                        Button("恢复默认") {
                            settings.resetToDefaults()
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 430, height: 760)
        .onAppear {
            if todayTasksStore.hasConfiguredToken, todayTasksStore.state == .idle {
                todayTasksStore.refresh()
            }
        }
    }
}

private struct TodayTasksOrderingSection: View {
    @ObservedObject var store: TodayTasksStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    store.hasConfiguredToken ? "已连接 Todoist" : "未检测到 Token",
                    systemImage: store.hasConfiguredToken ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(store.hasConfiguredToken ? .green.opacity(0.95) : .yellow.opacity(0.95))

                Spacer()

                Button("刷新任务") {
                    store.refresh()
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }

            if let actionMessage = store.actionMessage {
                Text(actionMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }

            switch store.state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.cyan)
                    Text("正在读取今日任务…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                }
            case .missingToken:
                Text("当前还没有检测到 Todoist Token，所以没法拉取今天的任务。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            case let .failed(message):
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            case .empty:
                Text("今天的 Todoist 任务目前为空。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            case .loaded:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.orderedTasks.enumerated()), id: \.element.id) { index, task in
                        TodayTaskOrderingRow(
                            index: index,
                            task: task,
                            isPrimary: index == 0,
                            canMoveUp: index > 0,
                            canMoveDown: index < store.orderedTasks.count - 1,
                            onMoveUp: { store.moveTaskUp(taskID: task.id) },
                            onMoveDown: { store.moveTaskDown(taskID: task.id) },
                            onMoveToTop: { store.moveTaskToTop(taskID: task.id) }
                        )
                    }
                }
            }
        }
    }
}

private struct TodayTaskOrderingRow: View {
    let index: Int
    let task: TodoistTask
    let isPrimary: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToTop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(isPrimary ? .cyan.opacity(0.96) : .white.opacity(0.72))
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.content)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(2)

                    if isPrimary {
                        Text("气泡显示")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.cyan.opacity(0.92))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.cyan.opacity(0.14))
                            )
                    }
                }

                HStack(spacing: 8) {
                    if let dueText = task.compactDueSummary {
                        Text(dueText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    if !task.labels.isEmpty {
                        Text(task.labels.map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button("置顶", action: onMoveToTop)
                    .buttonStyle(SettingsMiniButtonStyle())
                    .disabled(isPrimary)

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .disabled(!canMoveUp)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .disabled(!canMoveDown)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(isPrimary ? 0.24 : 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isPrimary ? .cyan.opacity(0.18) : .white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct SettingsCommandLine: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            Text(command)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black.opacity(0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        )
                )
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            content
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.10 : 0.06))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }
}

private struct SettingsMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.90))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : 0.08))
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}
