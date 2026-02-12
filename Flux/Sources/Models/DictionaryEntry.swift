import Foundation

struct DictionaryEntry: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String
    var aliases: [String]
    var description: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        aliases: [String] = [],
        description: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.aliases = aliases
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
