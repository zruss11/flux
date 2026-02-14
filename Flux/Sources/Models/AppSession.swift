import Foundation

struct AppSession: Identifiable, Codable, Sendable {
    let id: UUID
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let startedAt: Date
    var endedAt: Date?
    var contextSummary: String?

    var durationSeconds: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    init(
        id: UUID = UUID(),
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        contextSummary: String? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.contextSummary = contextSummary
    }
}
