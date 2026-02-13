import Foundation

enum SpeechInputProvider: String, CaseIterable, Identifiable, Sendable {
    case apple = "apple"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return "Apple Speech"
        case .deepgram:
            return "Deepgram"
        }
    }

    var requiresSpeechRecognitionPermission: Bool {
        switch self {
        case .apple:
            return true
        case .deepgram:
            return false
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
