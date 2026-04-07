import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let defaultFocusMinutes = "settings.defaultFocusMinutes"
        static let widgetScale = "settings.widgetScale"
        static let enableStrongReminder = "settings.enableStrongReminder"
        static let playReminderSound = "settings.playReminderSound"
        static let showDragHandle = "settings.showDragHandle"
        static let todoistTaskOrder = "settings.todoistTaskOrder"
    }

    private let defaults: UserDefaults

    @Published var defaultFocusMinutes: Int {
        didSet {
            let clamped = min(max(defaultFocusMinutes, 5), 60)
            if defaultFocusMinutes != clamped {
                defaultFocusMinutes = clamped
                return
            }
            defaults.set(defaultFocusMinutes, forKey: Keys.defaultFocusMinutes)
        }
    }

    @Published var widgetScale: Double {
        didSet {
            let clamped = min(max(widgetScale, 0.8), 1.3)
            if abs(widgetScale - clamped) > .ulpOfOne {
                widgetScale = clamped
                return
            }
            defaults.set(widgetScale, forKey: Keys.widgetScale)
        }
    }

    @Published var enableStrongReminder: Bool {
        didSet {
            defaults.set(enableStrongReminder, forKey: Keys.enableStrongReminder)
        }
    }

    @Published var playReminderSound: Bool {
        didSet {
            defaults.set(playReminderSound, forKey: Keys.playReminderSound)
        }
    }

    @Published var showDragHandle: Bool {
        didSet {
            defaults.set(showDragHandle, forKey: Keys.showDragHandle)
        }
    }

    @Published private(set) var todoistTaskOrder: [String] {
        didSet {
            defaults.set(todoistTaskOrder, forKey: Keys.todoistTaskOrder)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultFocusMinutes = defaults.object(forKey: Keys.defaultFocusMinutes) as? Int ?? 15
        self.widgetScale = defaults.object(forKey: Keys.widgetScale) as? Double ?? 1.0
        self.enableStrongReminder = defaults.object(forKey: Keys.enableStrongReminder) as? Bool ?? true
        self.playReminderSound = defaults.object(forKey: Keys.playReminderSound) as? Bool ?? true
        self.showDragHandle = defaults.object(forKey: Keys.showDragHandle) as? Bool ?? true
        self.todoistTaskOrder = defaults.stringArray(forKey: Keys.todoistTaskOrder) ?? []
    }

    func resetToDefaults() {
        defaultFocusMinutes = 15
        widgetScale = 1.0
        enableStrongReminder = true
        playReminderSound = true
        showDragHandle = true
    }

    func setTodoistTaskOrder(_ order: [String]) {
        todoistTaskOrder = order
    }
}
