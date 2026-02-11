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

    init(
        id: UUID = UUID(),
        rawTranscript: String,
        cleanedText: String,
        enhancedText: String? = nil,
        finalText: String,
        duration: TimeInterval,
        timestamp: Date,
        targetApp: String?,
        enhancementMethod: EnhancementMethod
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
    }

    enum EnhancementMethod: String, Codable, Sendable {
        case none
        case foundationModels
        case claude
    }
}
