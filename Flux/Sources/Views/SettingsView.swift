import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""
    @AppStorage("chatTitleCreator") private var chatTitleCreatorRaw = ChatTitleCreator.foundationModels.rawValue
    @AppStorage("handsFreeEnabled") private var handsFreeEnabled = false
    @AppStorage("wakePhrase") private var wakePhrase = "Hey Flux"
    @AppStorage("handsFreesilenceTimeout") private var silenceTimeout = 1.5

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
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .navigationTitle("Settings")
        .sheet(isPresented: $showAutomationsManager) {
            AutomationsManagerView()
        }
    }
}
