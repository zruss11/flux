import Foundation

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case processing
    case completed
    case failed
}

struct MeetingUtterance: Identifiable, Codable, Sendable {
    let id: UUID
    let speakerIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        speakerIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.createdAt = createdAt
    }
}

struct Meeting: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let startedAt: Date
    var endedAt: Date?
    var status: MeetingStatus
    var utterances: [MeetingUtterance]
    var folderId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: MeetingStatus = .recording,
        utterances: [MeetingUtterance] = [],
        folderId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.utterances = utterances
        self.folderId = folderId
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var transcriptText: String {
        utterances
            .map { "Speaker \($0.speakerIndex + 1): \($0.text)" }
            .joined(separator: "\n")
    }

    var rttmText: String {
        utterances.map { utterance in
            let duration = max(0, utterance.endTime - utterance.startTime)
            return "SPEAKER meeting 1 \(String(format: "%.3f", utterance.startTime)) \(String(format: "%.3f", duration)) <NA> <NA> speaker_\(utterance.speakerIndex) <NA> <NA>"
        }
        .joined(separator: "\n")
    }
}

struct MeetingSummary: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let startedAt: Date
    var endedAt: Date?
    var status: MeetingStatus
    var utteranceCount: Int
    var folderId: UUID?
    var updatedAt: Date

    init(from meeting: Meeting) {
        id = meeting.id
        title = meeting.title
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        status = meeting.status
        utteranceCount = meeting.utterances.count
        folderId = meeting.folderId
        updatedAt = meeting.endedAt ?? meeting.startedAt
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}
