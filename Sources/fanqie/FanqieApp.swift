import SwiftUI

@main
struct FanqieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(settings: AppSettings.shared)
        }
    }
}
