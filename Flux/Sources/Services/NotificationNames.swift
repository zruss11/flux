import Foundation

enum NotificationPayloadKey {
    static let conversationId = "conversationId"
    static let conversationTitle = "conversationTitle"
}

extension Notification.Name {
    static let telegramConfigDidChange = Notification.Name("telegramConfigDidChange")
    static let automationOpenThreadRequested = Notification.Name("automationOpenThreadRequested")
    static let islandOpenConversationRequested = Notification.Name("islandOpenConversationRequested")
    static let islandOpenFolderPickerRequested = Notification.Name("islandOpenFolderPickerRequested")
    static let islandOpenImagePickerRequested = Notification.Name("islandOpenImagePickerRequested")
    static let islandImageFilesSelected = Notification.Name("islandImageFilesSelected")
    static let islandStartTourRequested = Notification.Name("islandStartTourRequested")
    static let handsFreeConfigDidChange = Notification.Name("handsFreeConfigDidChange")
}

extension NotificationPayloadKey {
    static let imageURLs = "imageURLs"
}
