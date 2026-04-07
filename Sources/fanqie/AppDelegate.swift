import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var timerStore = TimerStore(settings: settings)
    private let todayTasksStore = TodayTasksStore.shared
    private var floatingPanelController: FloatingPanelController?
    private var completionOverlayController: CompletionOverlayController?
    private var settingsWindowController: SettingsWindowController?
    private var todayTasksWindowController: TodayTasksWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        timerStore.onCompletion = { [weak self] in
            self?.showCompletionOverlay()
        }
        if todayTasksStore.refreshTokenAvailability() {
            todayTasksStore.refresh()
        }
        installStatusItem()
        showPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc
    private func togglePanel() {
        guard let controller = floatingPanelController else {
            showPanel()
            return
        }

        controller.toggleWidgetVisibility()
    }

    @objc
    private func showPanel() {
        if floatingPanelController == nil {
            floatingPanelController = FloatingPanelController(
                timerStore: timerStore,
                todayTasksStore: todayTasksStore,
                settings: settings,
                onTestReminder: { [weak self] in
                    self?.showCompletionOverlay()
                },
                onOpenTasks: { [weak self] in
                    self?.showTodayTasksWindow()
                },
                onOpenSettings: { [weak self] in
                    self?.showSettingsWindow()
                }
            )
        }

        if todayTasksStore.refreshTokenAvailability(), todayTasksStore.state == .idle {
            todayTasksStore.refresh()
        }

        floatingPanelController?.presentWidget()
    }

    @objc
    private func triggerReminderTest() {
        showCompletionOverlay()
    }

    @objc
    private func showTodayTasksWindow() {
        if todayTasksWindowController == nil {
            todayTasksWindowController = TodayTasksWindowController(store: todayTasksStore)
        }

        todayTasksWindowController?.present(refresh: true)
    }

    @objc
    private func refreshTodayTasks() {
        todayTasksStore.refresh()

        if todayTasksWindowController?.window?.isVisible == true {
            todayTasksWindowController?.present(refresh: false)
        }
    }

    @objc
    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                todayTasksStore: todayTasksStore
            )
        }

        settingsWindowController?.present()
    }

    private func showCompletionOverlay() {
        guard settings.enableStrongReminder else {
            if settings.playReminderSound {
                CompletionOverlayController.playAlertBurst()
            }
            return
        }

        if completionOverlayController == nil {
            completionOverlayController = CompletionOverlayController(
                onRestart: { [weak self] in
                    guard let self else { return }
                    self.dismissCompletionOverlay()
                    self.timerStore.restartCurrentDuration()
                },
                onDismiss: { [weak self] in
                    self?.dismissCompletionOverlay()
                }
            )
        }

        completionOverlayController?.present(playSound: settings.playReminderSound)
    }

    private func dismissCompletionOverlay() {
        completionOverlayController?.dismissOverlay()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "番茄"

        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "显示或隐藏悬浮窗", action: #selector(togglePanel), keyEquivalent: "s")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let showItem = NSMenuItem(title: "重新打开", action: #selector(showPanel), keyEquivalent: "o")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let todayTasksItem = NSMenuItem(title: "今日任务…", action: #selector(showTodayTasksWindow), keyEquivalent: "d")
        todayTasksItem.target = self
        menu.addItem(todayTasksItem)

        let refreshTasksItem = NSMenuItem(title: "刷新今日任务", action: #selector(refreshTodayTasks), keyEquivalent: "r")
        refreshTasksItem.target = self
        menu.addItem(refreshTasksItem)

        menu.addItem(.separator())

        let testReminderItem = NSMenuItem(title: "测试强提醒", action: #selector(triggerReminderTest), keyEquivalent: "t")
        testReminderItem.target = self
        menu.addItem(testReminderItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }
}
