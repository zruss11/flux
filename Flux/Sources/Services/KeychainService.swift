import Foundation
import Security

enum KeychainService {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "Flux"
    }

    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    static func getString(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            return nil
        }
        guard let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func setString(_ value: String, forKey key: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteValue(forKey: key)
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let updateAttrs: [CFString: Any] = [
            kSecValueData: Data(trimmed.utf8)
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            let addQuery: [CFString: Any] = query.merging(
                [
                    kSecValueData: Data(trimmed.utf8),
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
                ],
                uniquingKeysWith: { $1 }
            )

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw Error.unexpectedStatus(updateStatus)
        }
    }

    static func deleteValue(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.unexpectedStatus(status)
        }
    }
}

