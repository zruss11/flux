import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordWebhookUrl") private var discordWebhookUrl = ""
    @AppStorage("slackWebhookUrl") private var slackWebhookUrl = ""

    var body: some View {
        Form {
            Section("AI") {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Link("Get API Key",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
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
