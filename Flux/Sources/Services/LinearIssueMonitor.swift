import Foundation
import os

struct LinearIssueSnapshot: Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let url: String?
    let stateName: String
    let stateType: String
    let priority: Int
    let teamKey: String?
    let updatedAt: Date
}

@MainActor
@Observable
final class LinearIssueMonitor {
    static let shared = LinearIssueMonitor()

    private(set) var issues: [LinearIssueSnapshot] = []
    private(set) var isLoading = false
    private(set) var isConfigured = false
    private(set) var lastError: String?

    private var timer: Timer?
    private var refreshGeneration: UInt64 = 0
    private var keyObserver: NSObjectProtocol?

    private let pollInterval: TimeInterval = 75
    private let maxIssues = 5

    private init() {
        keyObserver = NotificationCenter.default.addObserver(
            forName: .linearApiKeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    func start() {
        stop()

        Task {
            await refresh()
        }

        let nextTimer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        invalidateRefreshes()
    }

    func forceRefresh() {
        Task {
            await refresh()
        }
    }

    private func refresh() async {
        let generation = nextRefreshGeneration()

        let token = resolveApiKey()
        isConfigured = !token.isEmpty

        guard !token.isEmpty else {
            issues = []
            lastError = nil
            isLoading = false
            return
        }

        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        do {
            let fetchedIssues = try await fetchAssignedIssues(apiKey: token)
            guard generation == refreshGeneration else { return }

            issues = fetchedIssues
            lastError = nil
        } catch {
            Log.app.error("LinearIssueMonitor: failed to refresh issues — \(error.localizedDescription)")
            guard generation == refreshGeneration else { return }

            issues = []
            lastError = "Could not load Linear issues"
        }
    }

    private func fetchAssignedIssues(apiKey: String) async throws -> [LinearIssueSnapshot] {
        let query = """
        query FluxAtAGlanceLinearIssues($first: Int!) {
          viewer {
            id
          }
          issues(first: $first, orderBy: updatedAt) {
            nodes {
              id
              identifier
              title
              url
              updatedAt
              priority
              assignee {
                id
              }
              state {
                name
                type
              }
              team {
                key
              }
            }
          }
        }
        """

        let body = GraphQLBody(query: query, variables: Variables(first: 80))

        let responseData = try await executeGraphQL(body: body, apiKey: apiKey)
        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: responseData)

        if let firstError = decoded.errors?.first?.message, !firstError.isEmpty {
            throw LinearMonitorError.api(firstError)
        }

        guard let data = decoded.data else {
            throw LinearMonitorError.api("No data returned")
        }

        let viewerId = data.viewer.id
        let openIssues = data.issues.nodes
            .filter { issue in
                guard let assigneeId = issue.assignee?.id else { return false }
                guard assigneeId == viewerId else { return false }

                let stateType = (issue.state?.type ?? "").lowercased()
                return !["completed", "canceled", "cancelled", "done"].contains(stateType)
            }
            .map { issue in
                LinearIssueSnapshot(
                    id: issue.id,
                    identifier: issue.identifier,
                    title: issue.title,
                    url: issue.url,
                    stateName: issue.state?.name ?? "Open",
                    stateType: issue.state?.type ?? "unstarted",
                    priority: issue.priority,
                    teamKey: issue.team?.key,
                    updatedAt: parseISO8601(issue.updatedAt)
                )
            }
            .sorted { lhs, rhs in
                if normalizedPriority(lhs.priority) != normalizedPriority(rhs.priority) {
                    return normalizedPriority(lhs.priority) < normalizedPriority(rhs.priority)
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        return Array(openIssues.prefix(maxIssues))
    }

    private func executeGraphQL(body: GraphQLBody, apiKey: String) async throws -> Data {
        // Linear accepts raw API keys in `Authorization`, but retry with Bearer
        // for compatibility with some key formats.
        do {
            return try await executeGraphQL(body: body, apiKey: apiKey, useBearerPrefix: false)
        } catch {
            return try await executeGraphQL(body: body, apiKey: apiKey, useBearerPrefix: true)
        }
    }

    private func executeGraphQL(body: GraphQLBody, apiKey: String, useBearerPrefix: Bool) async throws -> Data {
        guard let url = URL(string: "https://api.linear.app/graphql") else {
            throw LinearMonitorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            useBearerPrefix ? "Bearer \(apiKey)" : apiKey,
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LinearMonitorError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LinearMonitorError.http(errorMessage)
        }

        return data
    }

    private func resolveApiKey() -> String {
        let keychainValue = (KeychainService.getString(forKey: SecretKeys.linearApiKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !keychainValue.isEmpty {
            return keychainValue
        }

        // Backwards-compatible fallback for users who only set the MCP token.
        return (UserDefaults.standard.string(forKey: "linearMcpToken") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseISO8601(_ value: String?) -> Date {
        guard let value else { return .distantPast }

        if let parsed = Self.iso8601Fractional.date(from: value) {
            return parsed
        }

        if let parsed = Self.iso8601.date(from: value) {
            return parsed
        }

        return .distantPast
    }

    private func normalizedPriority(_ value: Int) -> Int {
        // Linear: 0 = none, 1 = urgent, 2 = high, 3 = medium, 4 = low
        // Treat 0 as lowest priority in sorting.
        value == 0 ? 5 : value
    }

    private func nextRefreshGeneration() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    private func invalidateRefreshes() {
        refreshGeneration &+= 1
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct GraphQLBody: Encodable {
        let query: String
        let variables: Variables
    }

    private struct Variables: Encodable {
        let first: Int
    }

    private struct GraphQLResponse: Decodable {
        let data: DataPayload?
        let errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable {
        let message: String?
    }

    private struct DataPayload: Decodable {
        let viewer: Viewer
        let issues: IssueConnection
    }

    private struct Viewer: Decodable {
        let id: String
    }

    private struct IssueConnection: Decodable {
        let nodes: [IssueNode]
    }

    private struct IssueNode: Decodable {
        let id: String
        let identifier: String
        let title: String
        let url: String?
        let updatedAt: String?
        let priority: Int
        let assignee: Assignee?
        let state: State?
        let team: Team?
    }

    private struct Assignee: Decodable {
        let id: String
    }

    private struct State: Decodable {
        let name: String?
        let type: String?
    }

    private struct Team: Decodable {
        let key: String?
    }

    private enum LinearMonitorError: Error {
        case invalidURL
        case invalidResponse
        case http(String)
        case api(String)
    }
}
