import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordChannelId") private var discordChannelId = ""
    @AppStorage("slackChannelId") private var slackChannelId = ""
    @AppStorage("telegramChatId") private var telegramChatId = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""
    @AppStorage("chatTitleCreator") private var chatTitleCreatorRaw = ChatTitleCreator.foundationModels.rawValue
    @AppStorage("handsFreeEnabled") private var handsFreeEnabled = false
    @AppStorage("wakePhrase") private var wakePhrase = "Hey Flux"
    @AppStorage("handsFreesilenceTimeout") private var silenceTimeout = 1.5

    @State private var discordBotToken = ""
    @State private var slackBotToken = ""
    @State private var telegramBotToken = ""
    @State private var secretsLoaded = false
    @State private var telegramPairingCode = ""
    @State private var telegramPending: [TelegramPairingRequest] = []
    @State private var pairingError: String?
    @State private var automationService = AutomationService.shared
    @State private var showAutomationsManager = false

    var body: some View {
        Form {
            Section("AI") {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Link("Get API Key",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)

                Picker("Chat Title Creator", selection: $chatTitleCreatorRaw) {
                    ForEach(ChatTitleCreator.allCases) { creator in
                        Text(creator.displayName).tag(creator.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Controls how Flux generates titles for new chats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hands-Free") {
                Toggle("Enable Hands-Free Mode", isOn: $handsFreeEnabled)
                    .onChange(of: handsFreeEnabled) {
                        NotificationCenter.default.post(name: .handsFreeConfigDidChange, object: nil)
                    }

                if handsFreeEnabled {
                    TextField("Wake Phrase", text: $wakePhrase)
                        .textFieldStyle(.roundedBorder)

                    Text("Say this phrase to activate Flux. Default: \"Hey Flux\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper(
                        "Silence Timeout: \(String(format: "%.1f", silenceTimeout))s",
                        value: $silenceTimeout,
                        in: 0.5...5.0,
                        step: 0.5
                    )

                    Text("How long to wait after you stop speaking before sending the message.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("MCP") {
                SecureField("Linear MCP Token", text: $linearMcpToken)
                    .textFieldStyle(.roundedBorder)

                Text("Used for Linear issue/project tools in the agent sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automations") {
                HStack {
                    Text("Configured")
                    Spacer()
                    Text("\(automationService.automations.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Active")
                    Spacer()
                    Text("\(automationService.activeCount)")
                        .foregroundStyle(.secondary)
                }

                Button("Manage Automations") {
                    showAutomationsManager = true
                }
            }

            Section("Integrations") {
                SecureField("Discord Bot Token", text: $discordBotToken)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: discordBotToken) {
                        persistDiscordBotToken()
                    }

                TextField("Discord Channel ID", text: $discordChannelId)
                    .textFieldStyle(.roundedBorder)
                    .help(discordBotHelp)

                SecureField("Slack Bot Token", text: $slackBotToken)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: slackBotToken) {
                        persistSlackBotToken()
                    }

                TextField("Slack Channel ID", text: $slackChannelId)
                    .textFieldStyle(.roundedBorder)
                    .help(slackBotHelp)

                SecureField("Telegram Bot Token", text: $telegramBotToken)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: telegramBotToken) {
                        persistTelegramBotToken()
                    }

                TextField("Telegram Chat ID", text: $telegramChatId)
                    .textFieldStyle(.roundedBorder)
                    .help(telegramBotHelp)
                    .onChange(of: telegramChatId) {
                        notifyTelegramConfigChanged()
                    }
            }

            Section("Telegram Pairing") {
                if telegramPending.isEmpty {
                    Text("No pending pairing requests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(telegramPending) { request in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.username.map { "@\($0)" } ?? "Chat \(request.chatId)")
                                    .font(.subheadline)
                                Text("Chat ID: \(request.chatId)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                TelegramPairingStore.removePending(chatId: request.chatId)
                                loadPendingPairings()
                            }
                        }
                    }
                }

                HStack {
                    TextField("Pairing code", text: $telegramPairingCode)
                        .textFieldStyle(.roundedBorder)
                    Button("Approve") {
                        approveTelegramPairing()
                    }
                    .disabled(telegramPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let pairingError {
                    Text(pairingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
        .onAppear {
            loadSecretsIfNeeded()
            loadPendingPairings()
        }
        .sheet(isPresented: $showAutomationsManager) {
            AutomationsManagerView()
        }
    }

    private var discordBotHelp: String {
        [
            "Discord bot setup:",
            "1) Create a bot at Discord Developer Portal (Applications -> Bot).",
            "2) Copy the bot token and paste it into Flux.",
            "3) Invite the bot to your server with \"Send Messages\" permission.",
            "4) Enable Developer Mode in Discord, then right click a channel -> Copy Channel ID.",
            "",
            "Full guide: docs/bot-setup.md",
        ].joined(separator: "\n")
    }

    private var slackBotHelp: String {
        [
            "Slack bot setup:",
            "1) Create a Slack app (From scratch) with a Bot user.",
            "2) Under OAuth & Permissions, add scopes: chat:write (+ chat:write.public for public channels without inviting the bot).",
            "3) Install the app and copy the Bot User OAuth Token (xoxb-...).",
            "4) Copy the channel ID (starts with C or G). Invite the bot for private channels.",
            "",
            "Full guide: docs/bot-setup.md",
        ].joined(separator: "\n")
    }

    private var telegramBotHelp: String {
        [
            "Telegram bot setup:",
            "1) Create a bot with @BotFather and copy the token.",
            "2) Paste the token into Flux.",
            "3) Send your bot a DM to get a pairing code.",
            "4) Paste the pairing code in Flux to approve.",
            "5) For groups, mention @YourBotName to trigger responses.",
            "",
            "Full guide: docs/bot-setup.md",
        ].joined(separator: "\n")
    }

    private func loadSecretsIfNeeded() {
        guard !secretsLoaded else { return }
        secretsLoaded = true

        discordBotToken = KeychainService.getString(forKey: SecretKeys.discordBotToken) ?? ""
        slackBotToken = KeychainService.getString(forKey: SecretKeys.slackBotToken) ?? ""
        telegramBotToken = KeychainService.getString(forKey: SecretKeys.telegramBotToken) ?? ""
    }

    private func persistDiscordBotToken() {
        do {
            try KeychainService.setString(discordBotToken, forKey: SecretKeys.discordBotToken)
        } catch {
            // Best effort; ignore.
        }
    }

    private func persistSlackBotToken() {
        do {
            try KeychainService.setString(slackBotToken, forKey: SecretKeys.slackBotToken)
        } catch {
            // Best effort; ignore.
        }
    }

    private func persistTelegramBotToken() {
        do {
            try KeychainService.setString(telegramBotToken, forKey: SecretKeys.telegramBotToken)
        } catch {
            // Best effort; ignore.
        }
        notifyTelegramConfigChanged()
    }

    private func notifyTelegramConfigChanged() {
        NotificationCenter.default.post(name: .telegramConfigDidChange, object: nil)
    }

    private func loadPendingPairings() {
        telegramPending = TelegramPairingStore.loadPending()
    }

    private func approveTelegramPairing() {
        pairingError = nil
        let code = telegramPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let _ = TelegramPairingStore.approve(code: code) else {
            pairingError = "Pairing code not found or expired."
            return
        }
        telegramPairingCode = ""
        loadPendingPairings()
    }
}
