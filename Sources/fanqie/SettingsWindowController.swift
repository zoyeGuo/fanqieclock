import AppKit
import SwiftUI

enum WidgetLayout {
    static let baseWidth: CGFloat = 290
    static let baseHeightWithHandle: CGFloat = 300
    static let baseHeightWithoutHandle: CGFloat = 278
    static let baseDialSize: CGFloat = 272

    static func contentSize(scale: Double, showDragHandle: Bool) -> CGSize {
        CGSize(
            width: baseWidth * scale,
            height: (showDragHandle ? baseHeightWithHandle : baseHeightWithoutHandle) * scale
        )
    }

    static func panelSize(scale: Double, showDragHandle: Bool) -> CGSize {
        let content = contentSize(scale: scale, showDragHandle: showDragHandle)
        return CGSize(width: content.width + 10, height: content.height + 18)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings) {
        let rootView = SettingsRootView(settings: settings)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 470),
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
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: AppSettings

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
        .frame(width: 430, height: 470)
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
