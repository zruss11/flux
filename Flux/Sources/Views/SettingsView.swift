import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordWebhookUrl") private var discordWebhookUrl = ""
    @AppStorage("slackWebhookUrl") private var slackWebhookUrl = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""

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
                TextField("Discord Webhook URL", text: $discordWebhookUrl)
                    .textFieldStyle(.roundedBorder)

                TextField("Slack Webhook URL", text: $slackWebhookUrl)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
    }
}
