import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordChannelId") private var discordChannelId = ""
    @AppStorage("slackChannelId") private var slackChannelId = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""

    @State private var discordBotToken = ""
    @State private var slackBotToken = ""
    @State private var secretsLoaded = false

    var body: some View {
        Form {
            Section("AI") {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Link("Get API Key",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }

            Section("MCP") {
                SecureField("Linear MCP Token", text: $linearMcpToken)
                    .textFieldStyle(.roundedBorder)

                Text("Used for Linear issue/project tools in the agent sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
        .onAppear {
            loadSecretsIfNeeded()
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

    private func loadSecretsIfNeeded() {
        guard !secretsLoaded else { return }
        secretsLoaded = true

        discordBotToken = KeychainService.getString(forKey: SecretKeys.discordBotToken) ?? ""
        slackBotToken = KeychainService.getString(forKey: SecretKeys.slackBotToken) ?? ""
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
}
