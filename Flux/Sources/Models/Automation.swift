import Foundation

struct Automation: Identifiable, Codable, Hashable {
    enum Status: String, Codable, CaseIterable {
        case active
        case paused
    }

    let id: String
    var conversationId: String
    var name: String
    var prompt: String
    var scheduleExpression: String
    var timezoneIdentifier: String
    var status: Status
    let createdAt: Date
    var updatedAt: Date
    var nextRunAt: Date?
    var lastRunAt: Date?
    var lastRunSummary: String?

    init(
        id: String = UUID().uuidString,
        conversationId: String = UUID().uuidString,
        name: String,
        prompt: String,
        scheduleExpression: String,
        timezoneIdentifier: String = TimeZone.current.identifier,
        status: Status = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nextRunAt: Date? = nil,
        lastRunAt: Date? = nil,
        lastRunSummary: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.name = name
        self.prompt = prompt
        self.scheduleExpression = scheduleExpression
        self.timezoneIdentifier = timezoneIdentifier
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastRunSummary = lastRunSummary
    }
}

