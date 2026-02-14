import Foundation

struct ClipboardEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let content: String
    let timestamp: Date
    let sourceApp: String?
    let contentType: ContentType

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        sourceApp: String?,
        contentType: ContentType = .plainText
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.contentType = contentType
    }

    enum ContentType: String, Codable, Sendable {
        case plainText
        case url
        case filePath
    }
}
