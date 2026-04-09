import Combine
import Foundation

@MainActor
final class TimerStore: ObservableObject {
    enum Status {
        case idle
        case running
        case paused
        case completed
    }

    let maxMinutes = 60

    private let settings: AppSettings

    @Published private(set) var selectedDuration: TimeInterval
    @Published private(set) var remainingTime: TimeInterval
    @Published private(set) var status: Status = .idle

    var onCompletion: (() -> Void)?
    var onSessionCompleted: ((TimeInterval) -> Void)?

    private var timer: Timer?
    private var lastTick = Date()
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        let initialDuration = TimeInterval(settings.defaultFocusMinutes * 60)
        self.selectedDuration = initialDuration
        self.remainingTime = initialDuration
        bindSettings()
    }

    var dialFraction: Double {
        max(0, min(1, activeTime / maxDuration))
    }

    var displayTime: String {
        let totalSeconds = Int(activeTime.rounded(.up))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var subtitle: String {
        switch status {
        case .idle:
            return "拖动外圈设定时长"
        case .running:
            return "点击猫脸暂停"
        case .paused:
            return "点击猫脸继续"
        case .completed:
            return "已归零，点击重新开始"
        }
    }

    var footer: String {
        switch status {
        case .idle:
            return "顺时针拖动外圈，四分之一圈是 15 分钟"
        case .running:
            return "剩余时间减少时，指针会沿圆环回到原点"
        case .paused:
            return "右键可快速重置或切换常用时长"
        case .completed:
            return "倒计时结束，指针回到 12 点"
        }
    }

    var centerGlowStrength: Double {
        switch status {
        case .idle: 0.65
        case .running: 1.0
        case .paused: 0.45
        case .completed: 0.8
        }
    }

    var eyeColorProgress: Double {
        dialFraction
    }

    func setDuration(using fraction: Double) {
        guard status != .running else { return }

        let clamped = max(0, min(1, fraction))
        let minutes = max(1, Int((clamped * Double(maxMinutes)).rounded()))
        let seconds = TimeInterval(minutes * 60)
        selectedDuration = seconds
        remainingTime = seconds
        status = .idle
    }

    func setPreset(minutes: Int) {
        setDuration(using: Double(minutes) / Double(maxMinutes))
    }

    func togglePrimaryAction() {
        switch status {
        case .idle:
            start()
        case .running:
            pause()
        case .paused:
            resume()
        case .completed:
            reset()
            start()
        }
    }

    func reset() {
        stopTimer()
        remainingTime = selectedDuration
        status = .idle
    }

    func restartCurrentDuration() {
        reset()
        start()
    }

    private var activeTime: TimeInterval {
        status == .idle ? selectedDuration : remainingTime
    }

    private var maxDuration: TimeInterval {
        TimeInterval(maxMinutes * 60)
    }

    private func start() {
        if status == .completed {
            remainingTime = selectedDuration
        }

        lastTick = Date()
        status = .running
        installTimer()
    }

    private func resume() {
        lastTick = Date()
        status = .running
        installTimer()
    }

    private func pause() {
        stopTimer()
        status = .paused
    }

    private func complete() {
        stopTimer()
        remainingTime = 0
        status = .completed
        onSessionCompleted?(selectedDuration)
        onCompletion?()
    }

    private func installTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard status == .running else { return }

        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        remainingTime = max(0, remainingTime - delta)
        if remainingTime <= 0.001 {
            complete()
        }
    }

    private func bindSettings() {
        settings.$defaultFocusMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in
                guard let self else { return }
                guard self.status == .idle || self.status == .completed else { return }

                let duration = TimeInterval(minutes * 60)
                self.selectedDuration = duration
                if self.status == .idle {
                    self.remainingTime = duration
                }
            }
            .store(in: &cancellables)
    }
}
