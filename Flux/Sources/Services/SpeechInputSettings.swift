import Foundation

enum SpeechInputProvider: String, CaseIterable, Identifiable, Sendable {
    case parakeet = "parakeet"
    case apple = "apple"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeet:
            return "Parakeet TDT"
        case .apple:
            return "Apple Speech"
        case .deepgram:
            return "Deepgram"
        }
    }

    var requiresSpeechRecognitionPermission: Bool {
        switch self {
        case .parakeet:
            return false
        case .apple:
            return true
        case .deepgram:
            return false
        }
    }

    /// The `VoiceInputMode` to use when starting a recording with this provider.
    var voiceInputMode: VoiceInputMode {
        switch self {
        case .parakeet:
            return .parakeetOnDevice
        case .apple:
            return .live
        case .deepgram:
            return .live
        }
    }
}

enum SpeechInputSettings {
    static let providerStorageKey = "fluxSpeechInputProvider"
    static let deepgramApiKeyStorageKey = "deepgramApiKey"
}

extension UserDefaults {
    var speechInputProvider: SpeechInputProvider {
        get {
            let raw = string(forKey: SpeechInputSettings.providerStorageKey)
            return SpeechInputProvider(rawValue: raw ?? "") ?? .apple
        }
        set {
            setValue(newValue.rawValue, forKey: SpeechInputSettings.providerStorageKey)
        }
    }

    var deepgramApiKey: String {
        get { string(forKey: SpeechInputSettings.deepgramApiKeyStorageKey) ?? "" }
        set { setValue(newValue, forKey: SpeechInputSettings.deepgramApiKeyStorageKey) }
    }
}
