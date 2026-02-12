import Foundation

struct DictationEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let rawTranscript: String
    let cleanedText: String
    var enhancedText: String?
    var finalText: String
    let duration: TimeInterval
    let timestamp: Date
    let targetApp: String?
    let enhancementMethod: EnhancementMethod
    let status: Status
    let failureReason: String?

    init(
        id: UUID = UUID(),
        rawTranscript: String,
        cleanedText: String,
        enhancedText: String? = nil,
        finalText: String,
        duration: TimeInterval,
        timestamp: Date,
        targetApp: String?,
        enhancementMethod: EnhancementMethod,
        status: Status = .success,
        failureReason: String? = nil
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.cleanedText = cleanedText
        self.enhancedText = enhancedText
        self.finalText = finalText
        self.duration = duration
        self.timestamp = timestamp
        self.targetApp = targetApp
        self.enhancementMethod = enhancementMethod
        self.status = status
        self.failureReason = failureReason
    }

    enum EnhancementMethod: String, Codable, Sendable {
        case none
        case foundationModels
        case claude
    }

    enum Status: String, Codable, Sendable {
        case success
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rawTranscript
        case cleanedText
        case enhancedText
        case finalText
        case duration
        case timestamp
        case targetApp
        case enhancementMethod
        case status
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rawTranscript = try container.decode(String.self, forKey: .rawTranscript)
        cleanedText = try container.decode(String.self, forKey: .cleanedText)
        enhancedText = try container.decodeIfPresent(String.self, forKey: .enhancedText)
        finalText = try container.decode(String.self, forKey: .finalText)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        targetApp = try container.decodeIfPresent(String.self, forKey: .targetApp)
        enhancementMethod = try container.decode(EnhancementMethod.self, forKey: .enhancementMethod)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .success
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rawTranscript, forKey: .rawTranscript)
        try container.encode(cleanedText, forKey: .cleanedText)
        try container.encodeIfPresent(enhancedText, forKey: .enhancedText)
        try container.encode(finalText, forKey: .finalText)
        try container.encode(duration, forKey: .duration)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(targetApp, forKey: .targetApp)
        try container.encode(enhancementMethod, forKey: .enhancementMethod)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(failureReason, forKey: .failureReason)
    }
}
