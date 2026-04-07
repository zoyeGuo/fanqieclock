import Foundation

@MainActor
final class TodayTasksStore: ObservableObject {
    static let shared = TodayTasksStore(settings: AppSettings.shared)

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case missingToken
        case failed(String)
    }

    @Published private(set) var tasks: [TodoistTask] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var hasConfiguredToken: Bool
    @Published private(set) var completingTaskIDs: Set<String> = []
    @Published private(set) var actionMessage: String?

    private let settings: AppSettings
    private let client: TodoistClient
    private var refreshTask: Task<Void, Never>?
    private var completionTasks: [String: Task<Void, Never>] = [:]

    init(settings: AppSettings = .shared, client: TodoistClient = TodoistClient()) {
        self.settings = settings
        self.client = client
        self.hasConfiguredToken = TodoistClient.configuredToken != nil
    }

    deinit {
        refreshTask?.cancel()
    }

    var tokenEnvironmentKey: String {
        TodoistClient.tokenEnvironmentKey
    }

    var primaryTask: TodoistTask? {
        tasks.first
    }

    var orderedTasks: [TodoistTask] {
        tasks
    }

    func refresh() {
        refreshTokenAvailability()
        actionMessage = nil
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.loadTasks()
        }
    }

    @discardableResult
    func refreshTokenAvailability() -> Bool {
        let isAvailable = TodoistClient.configuredToken != nil
        hasConfiguredToken = isAvailable
        return isAvailable
    }

    func moveTaskUp(taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), index > 0 else { return }
        tasks.swapAt(index, index - 1)
        persistCurrentOrder()
    }

    func moveTaskDown(taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), index < tasks.count - 1 else { return }
        tasks.swapAt(index, index + 1)
        persistCurrentOrder()
    }

    func moveTaskToTop(taskID: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), index > 0 else { return }
        let task = tasks.remove(at: index)
        tasks.insert(task, at: 0)
        persistCurrentOrder()
    }

    func completeTask(taskID: String) {
        guard completionTasks[taskID] == nil else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performCompleteTask(taskID: taskID)
        }
        completionTasks[taskID] = task
    }

    func isCompleting(taskID: String) -> Bool {
        completingTaskIDs.contains(taskID)
    }

    private func loadTasks() async {
        state = .loading

        do {
            let tasks = try await client.fetchTodayTasks()
            hasConfiguredToken = true
            actionMessage = nil
            self.tasks = applyPersistedOrder(to: tasks)
            lastUpdatedAt = Date()
            state = self.tasks.isEmpty ? .empty : .loaded
            persistCurrentOrder()
        } catch is CancellationError {
            return
        } catch let error as TodoistClientError {
            tasks = []
            switch error {
            case .missingToken:
                hasConfiguredToken = false
                state = .missingToken
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            tasks = []
            state = .failed(error.localizedDescription)
        }
    }

    private func performCompleteTask(taskID: String) async {
        completingTaskIDs.insert(taskID)
        actionMessage = nil
        defer {
            completingTaskIDs.remove(taskID)
            completionTasks[taskID] = nil
        }

        do {
            try await client.closeTask(taskID: taskID)
            tasks.removeAll { $0.id == taskID }
            lastUpdatedAt = Date()
            state = tasks.isEmpty ? .empty : .loaded
            persistCurrentOrder()
            actionMessage = "任务已完成，已同步到 Todoist。"
        } catch is CancellationError {
            return
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func applyPersistedOrder(to fetchedTasks: [TodoistTask]) -> [TodoistTask] {
        guard !fetchedTasks.isEmpty else { return [] }

        let savedOrder = settings.todoistTaskOrder
        guard !savedOrder.isEmpty else { return fetchedTasks }

        let savedRanks = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
        let originalRanks = Dictionary(uniqueKeysWithValues: fetchedTasks.enumerated().map { ($1.id, $0) })

        return fetchedTasks.sorted { lhs, rhs in
            let lhsRank = savedRanks[lhs.id] ?? (savedOrder.count + (originalRanks[lhs.id] ?? 0))
            let rhsRank = savedRanks[rhs.id] ?? (savedOrder.count + (originalRanks[rhs.id] ?? 0))
            return lhsRank < rhsRank
        }
    }

    private func persistCurrentOrder() {
        settings.setTodoistTaskOrder(tasks.map(\.id))
    }
}
