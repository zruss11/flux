import Foundation

enum STTProvider: String, CaseIterable, Identifiable {
    case appleOnDevice
    case deepgram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice:
            return "Apple (On-Device)"
        case .deepgram:
            return "Deepgram (Live Streaming)"
        }
    }

    static var selected: STTProvider {
        let raw = UserDefaults.standard.string(forKey: STTSettings.providerKey) ?? STTProvider.appleOnDevice.rawValue
        return STTProvider(rawValue: raw) ?? .appleOnDevice
    }
}

enum STTSettings {
    static let providerKey = "sttProvider"
    static let deepgramAPIKey = "deepgramApiKey"
}
