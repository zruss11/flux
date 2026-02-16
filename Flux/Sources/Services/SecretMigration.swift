import Foundation

enum SecretKeys {
    static let discordBotToken = "discordBotToken"
    static let slackBotToken = "slackBotToken"
    static let telegramBotToken = "telegramBotToken"
}

enum ProviderKeys {
    static let anthropic = "providerKey_anthropic"
    static let openai = "providerKey_openai"
    static let google = "providerKey_google"
    static let groq = "providerKey_groq"
    static let xai = "providerKey_xai"
    static let openrouter = "providerKey_openrouter"
    static let mistral = "providerKey_mistral"
    static let cerebras = "providerKey_cerebras"

    static let allConfigs: [(id: String, label: String, keychainKey: String, placeholder: String)] = [
        ("anthropic", "Anthropic", anthropic, "sk-ant-..."),
        ("openai", "OpenAI", openai, "sk-..."),
        ("google", "Google Gemini", google, "AI..."),
        ("groq", "Groq", groq, "gsk_..."),
        ("xai", "xAI", xai, "xai-..."),
        ("openrouter", "OpenRouter", openrouter, "sk-or-..."),
        ("mistral", "Mistral", mistral, "..."),
        ("cerebras", "Cerebras", cerebras, "csk-..."),
    ]
}

enum SecretMigration {
    static func migrateUserDefaultsTokensToKeychainIfNeeded() {
        migrateKey(SecretKeys.discordBotToken)
        migrateKey(SecretKeys.slackBotToken)
        migrateKey(SecretKeys.telegramBotToken)
        migrateAnthropicApiKeyIfNeeded()
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

    private static func migrateAnthropicApiKeyIfNeeded() {
        let existingKeychain = (KeychainService.getString(forKey: ProviderKeys.anthropic) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existingDefaults = (UserDefaults.standard.string(forKey: "anthropicApiKey") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existingDefaults.isEmpty, existingKeychain.isEmpty else { return }

        do {
            try KeychainService.setString(existingDefaults, forKey: ProviderKeys.anthropic)
        } catch {
            // Best effort
        }
    }
}
