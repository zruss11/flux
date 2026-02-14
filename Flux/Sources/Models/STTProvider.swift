import Foundation
import Security

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

    /// Preferred `VoiceInputMode` for each provider — centralizes provider→mode mapping.
    var preferredVoiceInputMode: VoiceInputMode {
        switch self {
        case .deepgram: return .liveDeepgram
        case .appleOnDevice: return .batchOnDevice
        }
    }
}

enum STTSettings {
    static let providerKey = "sttProvider"
    /// Legacy UserDefaults key kept for migration.
    static let deepgramAPIKey = "deepgramApiKey"

    // MARK: - Keychain-backed Deepgram API key

    private static let keychainAccount = "com.flux.deepgramApiKey"

    /// Retrieve the Deepgram API key from Keychain (falling back to UserDefaults for migration).
    static var deepgramKey: String {
        if let keychainValue = readKeychain(account: keychainAccount), !keychainValue.isEmpty {
            return keychainValue
        }
        // Migrate from UserDefaults if present.
        let legacyValue = (UserDefaults.standard.string(forKey: deepgramAPIKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacyValue.isEmpty {
            setDeepgramKey(legacyValue)
            UserDefaults.standard.removeObject(forKey: deepgramAPIKey)
        }
        return legacyValue
    }

    /// Store the Deepgram API key in the Keychain.
    static func setDeepgramKey(_ value: String) {
        writeKeychain(account: keychainAccount, value: value)
    }

    // MARK: - Keychain helpers

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(account: String, value: String) {
        let data = Data(value.utf8)

        // Try to update existing item first.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
