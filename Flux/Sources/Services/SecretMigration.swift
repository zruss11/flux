import Foundation

enum SecretKeys {
    static let discordBotToken = "discordBotToken"
    static let slackBotToken = "slackBotToken"
    static let telegramBotToken = "telegramBotToken"
}

enum SecretMigration {
    static func migrateUserDefaultsTokensToKeychainIfNeeded() {
        migrateKey(SecretKeys.discordBotToken)
        migrateKey(SecretKeys.slackBotToken)
        migrateKey(SecretKeys.telegramBotToken)
    }

    private static func migrateKey(_ key: String) {
        let existingKeychain = (KeychainService.getString(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existingDefaults = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existingDefaults.isEmpty else { return }

        if existingKeychain.isEmpty {
            do {
                try KeychainService.setString(existingDefaults, forKey: key)
            } catch {
                // Best effort migration; ignore failure.
                return
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
    }
}
