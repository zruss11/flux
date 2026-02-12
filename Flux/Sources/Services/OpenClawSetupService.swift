import Foundation

struct OpenClawChannelAccount: Identifiable, Hashable {
    let provider: String
    let accountId: String

    var id: String { "\(provider):\(accountId)" }

    var providerDisplayName: String {
        switch provider.lowercased() {
        case "telegram": return "Telegram"
        case "slack": return "Slack"
        case "discord": return "Discord"
        default: return provider.capitalized
        }
    }
}

struct OpenClawModelProviderStatus: Hashable {
    let provider: String
    let profileCount: Int
    let oauthCount: Int
    let tokenCount: Int
    let apiKeyCount: Int
}

struct OpenClawSnapshot {
    let channels: [OpenClawChannelAccount]
    let authProfileCount: Int
    let gatewayReachable: Bool
    let gatewayError: String?
    let pluginsEnabled: [String: Bool]
    let pendingTelegramPairings: [OpenClawPairingRequest]
    let modelAuthStorePath: String?
    let modelProviders: [String: OpenClawModelProviderStatus]
    let missingModelProvidersInUse: Set<String>
}

struct OpenClawPairingRequest: Identifiable, Hashable {
    let code: String
    let label: String

    var id: String { code }
}

enum OpenClawSetupError: LocalizedError {
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}

enum OpenClawSetupService {
    static let defaultProfile = ProcessInfo.processInfo.environment["FLUX_OPENCLAW_PROFILE"] ?? "flux"

    static func snapshot(profile: String) async throws -> OpenClawSnapshot {
        async let channelsResult = run(profile: profile, arguments: ["channels", "list", "--json", "--no-usage"])
        async let statusResult = run(profile: profile, arguments: ["status", "--json"])
        async let modelsStatusResult = run(profile: profile, arguments: ["models", "status", "--json"])
        async let telegramEnabled = pluginEnabled(profile: profile, pluginId: "telegram")
        async let slackEnabled = pluginEnabled(profile: profile, pluginId: "slack")
        async let discordEnabled = pluginEnabled(profile: profile, pluginId: "discord")
        async let pairingResult = run(profile: profile, arguments: ["pairing", "list", "--channel", "telegram", "--json"])

        let channelsRaw = await channelsResult
        guard channelsRaw.status == 0 else {
            throw OpenClawSetupError.commandFailed(renderCommandFailure(action: "list channels", result: channelsRaw))
        }

        let channelsJSON = try parseJSONObject(from: channelsRaw.output)
        let channelAccounts = parseChannelAccounts(from: channelsJSON)
        let authCount = (channelsJSON["auth"] as? [Any])?.count ?? 0

        let statusRaw = await statusResult
        var gatewayReachable = false
        var gatewayError: String?

        if statusRaw.status == 0, let statusJSON = try? parseJSONObject(from: statusRaw.output) {
            if let gateway = statusJSON["gateway"] as? [String: Any] {
                gatewayReachable = gateway["reachable"] as? Bool ?? false
                gatewayError = gateway["error"] as? String
            }
        } else if isGatewayTokenMismatch(statusRaw.output) {
            // Sidecar runtime can rotate gateway token at startup; don't show a false "down"
            // status while config catches up.
            gatewayReachable = true
            gatewayError = nil
        } else {
            gatewayError = summarizeGatewayError(statusRaw.output)
        }

        let pluginsEnabled: [String: Bool] = [
            "telegram": await telegramEnabled,
            "slack": await slackEnabled,
            "discord": await discordEnabled,
        ]

        var pendingTelegramPairings: [OpenClawPairingRequest] = []
        let pairingsRaw = await pairingResult
        if pairingsRaw.status == 0,
           let pairingsJSON = try? parseJSONObject(from: pairingsRaw.output) {
            pendingTelegramPairings = parsePairingRequests(from: pairingsJSON)
        }

        var modelAuthStorePath: String?
        var modelProviders: [String: OpenClawModelProviderStatus] = [:]
        var missingModelProvidersInUse = Set<String>()

        let modelsStatusRaw = await modelsStatusResult
        if modelsStatusRaw.status == 0,
           let modelsJSON = try? parseJSONObject(from: modelsStatusRaw.output) {
            modelAuthStorePath = parseModelAuthStorePath(from: modelsJSON)
            modelProviders = parseModelProviderStatuses(from: modelsJSON)
            missingModelProvidersInUse = parseMissingModelProvidersInUse(from: modelsJSON)
        }

        return OpenClawSnapshot(
            channels: channelAccounts,
            authProfileCount: authCount,
            gatewayReachable: gatewayReachable,
            gatewayError: gatewayError,
            pluginsEnabled: pluginsEnabled,
            pendingTelegramPairings: pendingTelegramPairings,
            modelAuthStorePath: modelAuthStorePath,
            modelProviders: modelProviders,
            missingModelProvidersInUse: missingModelProvidersInUse
        )
    }

    static func connectTelegram(
        profile: String,
        token: String,
        accountId: String?,
        displayName: String?
    ) async throws -> String {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw OpenClawSetupError.commandFailed("Telegram token is required.")
        }

        try await ensurePluginEnabled(profile: profile, pluginId: "telegram")
        var args: [String] = ["channels", "add", "--channel", "telegram", "--token", trimmedToken]
        appendSharedChannelArgs(&args, accountId: accountId, displayName: displayName)
        let result = await run(profile: profile, arguments: args)
        guard result.status == 0 else {
            throw OpenClawSetupError.commandFailed(renderCommandFailure(action: "connect Telegram", result: result, redactions: [trimmedToken]))
        }
        return result.output.isEmpty ? "Telegram channel configured." : result.output
    }

    static func connectSlack(
        profile: String,
        botToken: String,
        appToken: String?,
        accountId: String?,
        displayName: String?
    ) async throws -> String {
        let trimmedBotToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBotToken.isEmpty else {
            throw OpenClawSetupError.commandFailed("Slack bot token is required.")
        }

        try await ensurePluginEnabled(profile: profile, pluginId: "slack")
        var args: [String] = ["channels", "add", "--channel", "slack", "--bot-token", trimmedBotToken]

        let trimmedAppToken = appToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAppToken.isEmpty {
            args.append(contentsOf: ["--app-token", trimmedAppToken])
        }

        appendSharedChannelArgs(&args, accountId: accountId, displayName: displayName)

        let result = await run(profile: profile, arguments: args)
        guard result.status == 0 else {
            throw OpenClawSetupError.commandFailed(
                renderCommandFailure(action: "connect Slack", result: result, redactions: [trimmedBotToken, trimmedAppToken])
            )
        }
        return result.output.isEmpty ? "Slack channel configured." : result.output
    }

    static func connectDiscord(
        profile: String,
        token: String,
        accountId: String?,
        displayName: String?
    ) async throws -> String {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw OpenClawSetupError.commandFailed("Discord bot token is required.")
        }

        try await ensurePluginEnabled(profile: profile, pluginId: "discord")
        var args: [String] = ["channels", "add", "--channel", "discord", "--token", trimmedToken]
        appendSharedChannelArgs(&args, accountId: accountId, displayName: displayName)

        let result = await run(profile: profile, arguments: args)
        guard result.status == 0 else {
            throw OpenClawSetupError.commandFailed(renderCommandFailure(action: "connect Discord", result: result, redactions: [trimmedToken]))
        }
        return result.output.isEmpty ? "Discord channel configured." : result.output
    }

    static func approveTelegramPairing(profile: String, code: String) async throws -> String {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw OpenClawSetupError.commandFailed("Pairing code is required.")
        }

        let result = await run(profile: profile, arguments: ["pairing", "approve", "--channel", "telegram", trimmedCode, "--notify"])
        guard result.status == 0 else {
            throw OpenClawSetupError.commandFailed(renderCommandFailure(action: "approve Telegram pairing", result: result))
        }

        return result.output.isEmpty ? "Telegram pairing approved." : result.output
    }

    static func configureModelApiKey(
        profile: String,
        provider: String,
        apiKey: String,
        profileId: String?
    ) async throws -> String {
        let providerId = normalizeProviderId(provider)
        guard !providerId.isEmpty else {
            throw OpenClawSetupError.commandFailed("Provider is required.")
        }

        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else {
            throw OpenClawSetupError.commandFailed("API key is required.")
        }

        let statusResult = await run(profile: profile, arguments: ["models", "status", "--json"])
        guard statusResult.status == 0 else {
            throw OpenClawSetupError.commandFailed(
                renderCommandFailure(action: "read model auth status", result: statusResult)
            )
        }

        let payload = try parseJSONObject(from: statusResult.output)
        let storePath = try resolveModelAuthStorePath(from: payload)
        let selectedProfileId = {
            let candidate = profileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.isEmpty ? "\(providerId):flux" : candidate
        }()

        do {
            try upsertModelApiKeyProfile(
                storePath: storePath,
                provider: providerId,
                profileId: selectedProfileId,
                apiKey: trimmedApiKey
            )
        } catch {
            throw OpenClawSetupError.commandFailed("Unable to update model auth store: \(error.localizedDescription)")
        }

        return "Saved \(providerDisplayName(providerId)) model auth profile \"\(selectedProfileId)\"."
    }

    private static func appendSharedChannelArgs(_ args: inout [String], accountId: String?, displayName: String?) {
        let trimmedAccount = accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAccount.isEmpty, trimmedAccount.lowercased() != "default" {
            args.append(contentsOf: ["--account", trimmedAccount])
        }

        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            args.append(contentsOf: ["--name", trimmedName])
        }
    }

    private static func ensurePluginEnabled(profile: String, pluginId: String) async throws {
        let result = await run(profile: profile, arguments: ["plugins", "enable", pluginId])
        guard result.status == 0 else {
            throw OpenClawSetupError.commandFailed(renderCommandFailure(action: "enable plugin \(pluginId)", result: result))
        }
    }

    private static func pluginEnabled(profile: String, pluginId: String) async -> Bool {
        let result = await run(profile: profile, arguments: ["plugins", "info", pluginId, "--json"])
        guard result.status == 0,
              let payload = try? parseJSONObject(from: result.output)
        else {
            return false
        }

        if let enabled = payload["enabled"] as? Bool {
            return enabled
        }

        if let status = payload["status"] as? String {
            return status == "loaded"
        }

        return false
    }

    private static func parseChannelAccounts(from payload: [String: Any]) -> [OpenClawChannelAccount] {
        guard let chat = payload["chat"] as? [String: Any] else {
            return []
        }

        var accounts: [OpenClawChannelAccount] = []

        for (provider, rawAccounts) in chat {
            if let values = rawAccounts as? [String] {
                for accountId in values {
                    accounts.append(OpenClawChannelAccount(provider: provider, accountId: accountId))
                }
                continue
            }

            if let values = rawAccounts as? [Any] {
                for raw in values {
                    let accountId = String(describing: raw)
                    accounts.append(OpenClawChannelAccount(provider: provider, accountId: accountId))
                }
                continue
            }

            accounts.append(OpenClawChannelAccount(provider: provider, accountId: "default"))
        }

        return accounts.sorted {
            if $0.provider == $1.provider {
                return $0.accountId < $1.accountId
            }
            return $0.provider < $1.provider
        }
    }

    private static func parsePairingRequests(from payload: [String: Any]) -> [OpenClawPairingRequest] {
        guard let requests = payload["requests"] as? [[String: Any]] else { return [] }
        return requests.compactMap { request in
            let code = (request["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else { return nil }

            if let sender = request["sender"] as? String, !sender.isEmpty {
                return OpenClawPairingRequest(code: code, label: sender)
            }
            if let from = request["from"] as? String, !from.isEmpty {
                return OpenClawPairingRequest(code: code, label: from)
            }
            if let rawChannel = request["channel"] as? String, !rawChannel.isEmpty {
                return OpenClawPairingRequest(code: code, label: rawChannel)
            }
            return OpenClawPairingRequest(code: code, label: "Pending request")
        }
    }

    private static func parseModelAuthStorePath(from payload: [String: Any]) -> String? {
        guard let auth = payload["auth"] as? [String: Any] else { return nil }
        return auth["storePath"] as? String
    }

    private static func parseModelProviderStatuses(from payload: [String: Any]) -> [String: OpenClawModelProviderStatus] {
        guard let auth = payload["auth"] as? [String: Any],
              let providers = auth["providers"] as? [[String: Any]]
        else {
            return [:]
        }

        var statuses: [String: OpenClawModelProviderStatus] = [:]

        for entry in providers {
            guard let rawProvider = entry["provider"] as? String else { continue }
            let provider = normalizeProviderId(rawProvider)
            guard !provider.isEmpty else { continue }

            let profileCounts = entry["profiles"] as? [String: Any]
            let status = OpenClawModelProviderStatus(
                provider: provider,
                profileCount: intValue(profileCounts?["count"]),
                oauthCount: intValue(profileCounts?["oauth"]),
                tokenCount: intValue(profileCounts?["token"]),
                apiKeyCount: intValue(profileCounts?["apiKey"])
            )

            statuses[provider] = status
        }

        return statuses
    }

    private static func parseMissingModelProvidersInUse(from payload: [String: Any]) -> Set<String> {
        guard let auth = payload["auth"] as? [String: Any],
              let providers = auth["missingProvidersInUse"] as? [Any]
        else {
            return []
        }

        var results = Set<String>()
        for rawProvider in providers {
            let normalized = normalizeProviderId(String(describing: rawProvider))
            if !normalized.isEmpty {
                results.insert(normalized)
            }
        }
        return results
    }

    private static func parseJSONObject(from output: String) throws -> [String: Any] {
        guard let jsonPayload = extractJSONPayload(from: output),
              let data = jsonPayload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw OpenClawSetupError.invalidResponse("OpenClaw returned non-JSON output.")
        }

        return object
    }

    private static func resolveModelAuthStorePath(from payload: [String: Any]) throws -> String {
        if let auth = payload["auth"] as? [String: Any],
           let storePath = auth["storePath"] as? String,
           !storePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storePath
        }

        if let agentDir = payload["agentDir"] as? String,
           !agentDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: agentDir).appendingPathComponent("auth-profiles.json").path
        }

        throw OpenClawSetupError.invalidResponse("OpenClaw did not return an auth store path.")
    }

    private static func upsertModelApiKeyProfile(
        storePath: String,
        provider: String,
        profileId: String,
        apiKey: String
    ) throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: storePath)
        let directoryURL = url.deletingLastPathComponent()
        try fm.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )

        var store = try loadAuthProfileStore(at: url)
        var profiles = store["profiles"] as? [String: Any] ?? [:]
        profiles[profileId] = [
            "type": "api_key",
            "provider": provider,
            "key": apiKey,
        ]
        store["profiles"] = profiles

        var order = store["order"] as? [String: Any] ?? [:]
        var providerOrder = (order[provider] as? [Any])?
            .compactMap { value -> String? in
                let entry = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                return entry.isEmpty ? nil : entry
            } ?? []
        providerOrder.removeAll(where: { $0 == profileId })
        providerOrder.insert(profileId, at: 0)
        order[provider] = providerOrder
        store["order"] = order

        if store["version"] == nil {
            store["version"] = 1
        }

        let data = try JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try setSecureFilePermissions(for: url)
    }

    private static func loadAuthProfileStore(at url: URL) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return [
                "version": 1,
                "profiles": [:],
            ]
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [
                "version": 1,
                "profiles": [:],
            ]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let store = object as? [String: Any] else {
            throw OpenClawSetupError.invalidResponse("Model auth store is not valid JSON.")
        }
        return store
    }

    private static func setSecureFilePermissions(for url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private static func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String, let parsed = Int(string) {
            return parsed
        }
        return 0
    }

    private static func normalizeProviderId(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func providerDisplayName(_ provider: String) -> String {
        switch provider {
        case "anthropic":
            return "Anthropic"
        case "openai":
            return "OpenAI"
        case "google":
            return "Google"
        default:
            return provider.capitalized
        }
    }

    private static func extractJSONPayload(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.first == "{" || trimmed.first == "[" {
            return trimmed
        }

        if let objectStart = trimmed.firstIndex(of: "{"),
           let objectEnd = trimmed.lastIndex(of: "}") {
            return String(trimmed[objectStart...objectEnd])
        }

        return nil
    }

    private static func isGatewayTokenMismatch(_ output: String) -> Bool {
        output.localizedCaseInsensitiveContains("gateway token mismatch")
            || output.localizedCaseInsensitiveContains("provide gateway auth token")
            || output.localizedCaseInsensitiveContains("unauthorized")
    }

    private static func summarizeGatewayError(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unable to read OpenClaw gateway status." }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return firstLine
    }

    private static func renderCommandFailure(action: String, result: CommandResult, redactions: [String] = []) -> String {
        var output = result.output
        for redaction in redactions where !redaction.isEmpty {
            output = output.replacingOccurrences(of: redaction, with: "[REDACTED]")
        }

        if result.timedOut {
            return "OpenClaw timed out while attempting to \(action)."
        }

        if output.isEmpty {
            return "OpenClaw failed to \(action) (exit code \(result.status))."
        }

        return "OpenClaw failed to \(action): \(output)"
    }

    private static func run(profile: String, arguments: [String], timeout: TimeInterval = 20) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["openclaw", "--profile", profile] + arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(status: -1, output: error.localizedDescription, timedOut: false))
                    return
                }

                let timeoutDate = Date().addingTimeInterval(timeout)
                while process.isRunning, Date() < timeoutDate {
                    Thread.sleep(forTimeInterval: 0.05)
                }

                var timedOut = false
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }

                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let status = timedOut ? -1 : process.terminationStatus
                continuation.resume(returning: CommandResult(status: status, output: output, timedOut: timedOut))
            }
        }
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let timedOut: Bool
    }
}
