import Foundation

struct FocusSessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let completedAt: Date
    let durationSeconds: Int

    init(id: UUID = UUID(), completedAt: Date, durationSeconds: Int) {
        self.id = id
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
    }
}

struct FocusSummary: Equatable {
    let totalDuration: TimeInterval
    let sessionCount: Int

    static let empty = FocusSummary(totalDuration: 0, sessionCount: 0)
}

@MainActor
final class FocusStatsStore: ObservableObject {
    static let shared = FocusStatsStore()

    private enum Keys {
        static let focusSessionRecords = "stats.focusSessionRecords"
    }

    @Published private(set) var records: [FocusSessionRecord] = []

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let retentionDays = 90

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRecords()
        pruneIfNeeded()
    }

    var todaySummary: FocusSummary {
        summary(for: .today)
    }

    var weekSummary: FocusSummary {
        summary(for: .week)
    }

    func recordCompletedSession(duration: TimeInterval, completedAt: Date = Date()) {
        let roundedDuration = Int(duration.rounded())
        guard roundedDuration > 0 else { return }

        records.insert(
            FocusSessionRecord(
                completedAt: completedAt,
                durationSeconds: roundedDuration
            ),
            at: 0
        )
        pruneIfNeeded()
        persist()
    }

    func clearHistory() {
        records = []
        persist()
    }

    func formattedDuration(for summary: FocusSummary) -> String {
        let totalMinutes = Int((summary.totalDuration / 60).rounded())
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours) 小时"
            }
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(totalMinutes) 分钟"
    }

    private func summary(for range: SummaryRange) -> FocusSummary {
        let calendar = Calendar.current
        let now = Date()

        let filteredRecords = records.filter { record in
            switch range {
            case .today:
                return calendar.isDate(record.completedAt, inSameDayAs: now)
            case .week:
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                    return false
                }
                return interval.contains(record.completedAt)
            }
        }

        let totalDuration = filteredRecords.reduce(0) { $0 + TimeInterval($1.durationSeconds) }
        return FocusSummary(totalDuration: totalDuration, sessionCount: filteredRecords.count)
    }

    private func loadRecords() {
        guard let data = defaults.data(forKey: Keys.focusSessionRecords) else {
            records = []
            return
        }

        do {
            records = try decoder.decode([FocusSessionRecord].self, from: data)
                .sorted(by: { $0.completedAt > $1.completedAt })
        } catch {
            records = []
        }
    }

    private func pruneIfNeeded() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast
        let pruned = records.filter { $0.completedAt >= cutoffDate }
        if pruned != records {
            records = pruned
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(records)
            defaults.set(data, forKey: Keys.focusSessionRecords)
        } catch {
            defaults.removeObject(forKey: Keys.focusSessionRecords)
        }
    }

    private enum SummaryRange {
        case today
        case week
    }
}
