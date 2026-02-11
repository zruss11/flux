import Foundation

// MARK: - Chat Folder

struct ChatFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    var conversationIds: [UUID]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), conversationIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.conversationIds = conversationIds
    }
}

// MARK: - Conversation Summary

/// Lightweight metadata used for the history list (avoids loading full messages).
struct ConversationSummary: Identifiable, Codable {
    let id: UUID
    var title: String
    let createdAt: Date
    var lastMessageAt: Date
    var messageCount: Int
    var folderId: UUID?

    /// Time-group label for display in the history panel.
    var timeGroup: TimeGroup {
        let cal = Calendar.current
        if cal.isDateInToday(lastMessageAt) { return .today }
        if cal.isDateInYesterday(lastMessageAt) { return .yesterday }
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()),
           lastMessageAt >= weekAgo { return .lastWeek }
        return .older
    }

    enum TimeGroup: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case lastWeek = "Last 7 Days"
        case older = "Older"
    }
}
