import Foundation

/// Represents a proactive alert from a Watcher.
struct WatcherAlert: Identifiable, Codable, Hashable, Sendable {
    enum Priority: String, Codable, CaseIterable, Comparable {
        case critical
        case high
        case medium
        case low
        case info

        private var sortOrder: Int {
            switch self {
            case .critical: 0
            case .high: 1
            case .medium: 2
            case .low: 3
            case .info: 4
            }
        }

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    let id: String
    let watcherId: String
    let watcherType: String
    let watcherName: String
    let priority: Priority
    let title: String
    let summary: String
    var details: String?
    var sourceUrl: String?
    var suggestedActions: [String]?
    let timestamp: Date
    let dedupeKey: String

    /// Whether the user has seen/dismissed this alert.
    var isDismissed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, watcherId, watcherType, watcherName, priority
        case title, summary, details, sourceUrl, suggestedActions
        case timestamp, dedupeKey, isDismissed
    }
}

/// Represents a proactive watcher configuration.
struct Watcher: Identifiable, Codable, Hashable, Sendable {
    enum WatcherType: String, Codable, CaseIterable {
        case email
        case github
        case custom
        case notificationDB

        var displayName: String {
            switch self {
            case .email: "Email"
            case .github: "GitHub"
            case .custom: "Custom"
            case .notificationDB: "Notifications"
            }
        }

        var iconName: String {
            switch self {
            case .email: "envelope.fill"
            case .github: "chevron.left.forwardslash.chevron.right"
            case .custom: "gearshape.fill"
            case .notificationDB: "bell.fill"
            }
        }

        var defaultIntervalSeconds: Int {
            switch self {
            case .email: 300           // 5 min
            case .github: 120          // 2 min
            case .custom: 300          // 5 min
            case .notificationDB: 30   // 30 sec
            }
        }
    }

    enum NotificationMode: String, Codable, CaseIterable {
        case native      // macOS notification only
        case chat        // Flux chat only
        case both        // both
        case silent      // no notification, just logged

        var displayName: String {
            switch self {
            case .native: "System Notification"
            case .chat: "Chat Message"
            case .both: "Both"
            case .silent: "Silent"
            }
        }
    }

    let id: String
    var name: String
    var type: WatcherType
    var enabled: Bool
    var intervalSeconds: Int
    var notificationMode: NotificationMode
    var settings: [String: String]
    let createdAt: Date
    var updatedAt: Date

    /// Credential key names needed for this watcher (e.g., "gmail_token").
    var credentialKeys: [String]

    static let minimumIntervalSeconds = 15
    static let maximumIntervalSeconds = 86_400

    init(
        id: String = UUID().uuidString,
        name: String,
        type: WatcherType,
        enabled: Bool = true,
        intervalSeconds: Int? = nil,
        notificationMode: NotificationMode = .both,
        settings: [String: String] = [:],
        credentialKeys: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.intervalSeconds = Self.clampIntervalSeconds(intervalSeconds ?? type.defaultIntervalSeconds)
        self.notificationMode = notificationMode
        self.settings = settings
        self.credentialKeys = credentialKeys
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func clampIntervalSeconds(_ value: Int) -> Int {
        min(max(value, minimumIntervalSeconds), maximumIntervalSeconds)
    }
}
