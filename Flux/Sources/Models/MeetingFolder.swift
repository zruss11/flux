import Foundation

struct MeetingFolder: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var meetingIds: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        meetingIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.meetingIds = meetingIds
    }
}
