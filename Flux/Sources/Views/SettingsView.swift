import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""
    @AppStorage("chatTitleCreator") private var chatTitleCreatorRaw = ChatTitleCreator.foundationModels.rawValue
    @AppStorage(STTSettings.providerKey) private var sttProviderRaw = STTProvider.appleOnDevice.rawValue
    @State private var deepgramAPIKey = STTSettings.deepgramKey

    @State private var automationService = AutomationService.shared
    @State private var showAutomationsManager = false

    var body: some View {
        Form {
            Section("Speech to Text") {
                Picker("Provider", selection: $sttProviderRaw) {
                    ForEach(STTProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)

                SecureField("Deepgram API Key", text: $deepgramAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: deepgramAPIKey) { _, newValue in
                        STTSettings.setDeepgramKey(newValue)
                    }

                if sttProviderRaw == STTProvider.deepgram.rawValue {
                    Text("Deepgram live streaming requires a valid API key when Provider is set to Deepgram.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
