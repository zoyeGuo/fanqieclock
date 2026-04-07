import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var timerStore = TimerStore(settings: settings)
    private var floatingPanelController: FloatingPanelController?
    private var completionOverlayController: CompletionOverlayController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        timerStore.onCompletion = { [weak self] in
            self?.showCompletionOverlay()
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

        if controller.panel.isVisible {
            controller.panel.orderOut(nil)
        } else {
            controller.showWindow(nil)
            controller.panel.orderFrontRegardless()
        }
    }

    @objc
    private func showPanel() {
        if floatingPanelController == nil {
            floatingPanelController = FloatingPanelController(
                timerStore: timerStore,
                settings: settings,
                onTestReminder: { [weak self] in
                    self?.showCompletionOverlay()
                },
                onOpenSettings: { [weak self] in
                    self?.showSettingsWindow()
                }
            )
        }

        floatingPanelController?.showWindow(nil)
        floatingPanelController?.panel.orderFrontRegardless()
    }

    @objc
    private func triggerReminderTest() {
        showCompletionOverlay()
    }

    @objc
    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
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
