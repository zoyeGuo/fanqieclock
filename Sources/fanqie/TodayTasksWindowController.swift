import AppKit
import SwiftUI

@MainActor
final class TodayTasksWindowController: NSWindowController {
    private let store: TodayTasksStore

    init(store: TodayTasksStore) {
        self.store = store

        let rootView = TodayTasksRootView(store: store)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "今日任务"
        window.minSize = NSSize(width: 420, height: 520)
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

    func present(refresh: Bool = true) {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)

        if refresh {
            store.refresh()
        }
    }
}

private struct TodayTasksRootView: View {
    @ObservedObject var store: TodayTasksStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.11, blue: 0.15),
                    Color(red: 0.03, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    switch store.state {
                    case .idle, .loading:
                        TodayTasksCard {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.cyan)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("正在读取今日任务")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("当前会使用 Todoist 的 `today` 过滤器拉取任务。")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.68))
                                }
                            }
                        }
                    case .missingToken:
                        tokenGuide
                    case let .failed(message):
                        errorCard(message: message)
                    case .empty:
                        emptyCard
                    case .loaded:
                        tasksList
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("这里会读取 Todoist 当天任务，适合在专注前快速看一下今天要做什么。")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Button("刷新") {
                    store.refresh()
                }
                .buttonStyle(TasksPrimaryButtonStyle())
            }

            HStack(spacing: 10) {
                Label(
                    store.hasConfiguredToken ? "已检测到 Token" : "未检测到 Token",
                    systemImage: store.hasConfiguredToken ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(store.hasConfiguredToken ? .green.opacity(0.95) : .yellow.opacity(0.95))

                if let lastUpdatedAt = store.lastUpdatedAt {
                    Text("上次更新 \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
    }

    private var tokenGuide: some View {
        TodayTasksCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("还没有配置 Todoist Token")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("先把 Todoist API Token 放进环境变量 `\(store.tokenEnvironmentKey)`，再重启 app。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                TodayTasksCommandBlock(
                    title: "终端运行可执行文件时",
                    command: "export \(store.tokenEnvironmentKey)=\"你的 Todoist Token\""
                )

                TodayTasksCommandBlock(
                    title: "像普通桌面 App 一样启动时",
                    command: "launchctl setenv \(store.tokenEnvironmentKey) \"你的 Todoist Token\""
                )

                Text("改完后请完全退出并重新打开 FanqieClock。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func errorCard(message: String) -> some View {
        TodayTasksCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("读取失败")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                Button("重新读取") {
                    store.refresh()
                }
                .buttonStyle(TasksPrimaryButtonStyle())
            }
        }
    }

    private var emptyCard: some View {
        TodayTasksCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("今天的 Todoist 任务已经清空了")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Todoist 的 `today` 过滤结果目前为空，专注计时器可以放心只盯当前这一轮。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private var tasksList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(store.tasks) { task in
                TodayTaskRow(task: task)
            }
        }
    }
}

private struct TodayTaskRow: View {
    let task: TodoistTask

    var body: some View {
        TodayTasksCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: priorityColor.opacity(0.7), radius: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.content)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        if !task.description.isEmpty {
                            Text(task.description)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.66))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if let dueText = task.compactDueSummary {
                        TodayTaskMetaPill(
                            text: dueText,
                            icon: "clock.fill",
                            tint: .cyan
                        )
                    }

                    if !task.labels.isEmpty {
                        TodayTaskMetaPill(
                            text: task.labels.map { "#\($0)" }.joined(separator: "  "),
                            icon: "tag.fill",
                            tint: .orange
                        )
                    }

                    Spacer(minLength: 0)

                    Text("P\(task.priority)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(priorityColor.opacity(0.95))
                }
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case 4: return Color(red: 0.95, green: 0.37, blue: 0.31)
        case 3: return Color(red: 0.96, green: 0.67, blue: 0.24)
        case 2: return Color(red: 0.34, green: 0.78, blue: 0.98)
        default: return Color.white.opacity(0.58)
        }
    }
}

private struct TodayTaskMetaPill: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(tint.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.20), lineWidth: 1)
                )
        )
    }
}

private struct TodayTasksCommandBlock: View {
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

private struct TodayTasksCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct TasksPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.cyan.opacity(configuration.isPressed ? 0.50 : 0.34))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}
