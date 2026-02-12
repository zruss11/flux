import Foundation

enum NotificationPayloadKey {
    static let conversationId = "conversationId"
    static let conversationTitle = "conversationTitle"
}

extension Notification.Name {
    static let telegramConfigDidChange = Notification.Name("telegramConfigDidChange")
    static let appInstructionsDidChange = Notification.Name("appInstructionsDidChange")
    static let automationOpenThreadRequested = Notification.Name("automationOpenThreadRequested")
    static let islandOpenConversationRequested = Notification.Name("islandOpenConversationRequested")
    static let islandOpenFolderPickerRequested = Notification.Name("islandOpenFolderPickerRequested")
    static let islandOpenImagePickerRequested = Notification.Name("islandOpenImagePickerRequested")
    static let islandImageFilesSelected = Notification.Name("islandImageFilesSelected")
    static let islandStartTourRequested = Notification.Name("islandStartTourRequested")
}

extension NotificationPayloadKey {
    static let imageURLs = "imageURLs"
}
