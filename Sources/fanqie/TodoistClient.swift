import Foundation

struct TodoistTaskPage: Decodable {
    let results: [TodoistTask]
    let nextCursor: String?
}

struct TodoistTask: Decodable, Identifiable, Hashable {
    let id: String
    let content: String
    let description: String
    let priority: Int
    let labels: [String]
    let due: TodoistDue?
}

struct TodoistDue: Decodable, Hashable {
    let date: String
    let datetime: String?
    let string: String
    let timezone: String?
    let isRecurring: Bool?
}

enum TodoistClientError: LocalizedError {
    case missingToken(environmentKey: String)
    case unauthorized
    case invalidResponse
    case unexpectedStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case let .missingToken(environmentKey):
            return "没有检测到 \(environmentKey)，请先配置 Todoist API Token。"
        case .unauthorized:
            return "Todoist Token 无效或已失效，请检查环境变量。"
        case .invalidResponse:
            return "Todoist 返回了无法识别的响应。"
        case let .unexpectedStatus(statusCode):
            return "Todoist 请求失败，状态码 \(statusCode)。"
        case .decodingFailed:
            return "Todoist 数据解析失败。"
        }
    }
}

struct TodoistClient {
    static let tokenEnvironmentKey = "TODOIST_API_TOKEN"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static var configuredToken: String? {
        if let token = normalizedToken(ProcessInfo.processInfo.environment[tokenEnvironmentKey]) {
            return token
        }

        return tokenFromLaunchCtl()
    }

    func fetchTodayTasks() async throws -> [TodoistTask] {
        guard let token = Self.configuredToken else {
            throw TodoistClientError.missingToken(environmentKey: Self.tokenEnvironmentKey)
        }

        var collectedTasks: [TodoistTask] = []
        var nextCursor: String?

        repeat {
            let request = try makeFilteredTasksRequest(token: token, cursor: nextCursor)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TodoistClientError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                throw TodoistClientError.unauthorized
            default:
                throw TodoistClientError.unexpectedStatus(httpResponse.statusCode)
            }

            let page: TodoistTaskPage
            do {
                page = try Self.decoder.decode(TodoistTaskPage.self, from: data)
            } catch {
                throw TodoistClientError.decodingFailed
            }

            collectedTasks.append(contentsOf: page.results)
            nextCursor = normalizedCursor(page.nextCursor)
        } while nextCursor != nil

        return sortTasks(collectedTasks)
    }

    func closeTask(taskID: String) async throws {
        guard let token = Self.configuredToken else {
            throw TodoistClientError.missingToken(environmentKey: Self.tokenEnvironmentKey)
        }

        let request = try makeCloseTaskRequest(taskID: taskID, token: token)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TodoistClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 204:
            return
        case 401:
            throw TodoistClientError.unauthorized
        default:
            throw TodoistClientError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    private func makeFilteredTasksRequest(token: String, cursor: String?) throws -> URLRequest {
        let filterURL = URL(string: "https://api.todoist.com/api/v1/tasks/filter")!
        var components = URLComponents(url: filterURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "query", value: "today"),
            URLQueryItem(name: "limit", value: "100")
        ]
        if let cursor = normalizedCursor(cursor) {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw TodoistClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private func makeCloseTaskRequest(taskID: String, token: String) throws -> URLRequest {
        guard let encodedTaskID = taskID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.todoist.com/rest/v2/tasks/\(encodedTaskID)/close")
        else {
            throw TodoistClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.timeoutInterval = 20
        return request
    }

    private func sortTasks(_ tasks: [TodoistTask]) -> [TodoistTask] {
        tasks.sorted { lhs, rhs in
            let lhsDate = lhs.due?.resolvedDate
            let rhsDate = rhs.due?.resolvedDate

            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate < rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }

            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            return lhs.content.localizedCaseInsensitiveCompare(rhs.content) == .orderedAscending
        }
    }

    private func normalizedCursor(_ cursor: String?) -> String? {
        guard let cursor else { return nil }
        let normalized = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func tokenFromLaunchCtl() -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["getenv", tokenEnvironmentKey]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        return normalizedToken(output)
    }

    private static func normalizedToken(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let token = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private extension TodoistDue {
    var resolvedDate: Date? {
        if let datetime {
            if let preciseDate = Self.preciseDateTimeFormatter().date(from: datetime) {
                return preciseDate
            }
            if let fallbackDate = Self.fallbackDateTimeFormatter().date(from: datetime) {
                return fallbackDate
            }
        }

        return Self.dayFormatter().date(from: date)
    }

    private static func preciseDateTimeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func fallbackDateTimeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

extension TodoistTask {
    var compactDueSummary: String? {
        guard let due else { return nil }

        if let datetime = due.datetime, let date = TodoistTaskDateParser.date(from: datetime) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if !due.date.isEmpty {
            return "今天"
        }

        return due.string.isEmpty ? nil : due.string
    }
}

private enum TodoistTaskDateParser {
    static func date(from iso8601: String) -> Date? {
        if let preciseDate = preciseFormatter().date(from: iso8601) {
            return preciseDate
        }
        return fallbackFormatter().date(from: iso8601)
    }

    private static func preciseFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func fallbackFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
