import SwiftUI

@main
struct FanqieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var todayTasksStore = TodayTasksStore.shared
    @StateObject private var focusStatsStore = FocusStatsStore.shared

    var body: some Scene {
        Settings {
            SettingsRootView(
                settings: AppSettings.shared,
                todayTasksStore: todayTasksStore,
                focusStatsStore: focusStatsStore
            )
        }
    }
}
