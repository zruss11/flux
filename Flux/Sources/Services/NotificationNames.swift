import Foundation

enum NotificationPayloadKey {
    static let conversationId = "conversationId"
    static let conversationTitle = "conversationTitle"
}

extension Notification.Name {
    static let telegramConfigDidChange = Notification.Name("telegramConfigDidChange")
    static let automationOpenThreadRequested = Notification.Name("automationOpenThreadRequested")
    static let islandOpenConversationRequested = Notification.Name("islandOpenConversationRequested")
}
