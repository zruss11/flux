import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""
    @AppStorage("chatTitleCreator") private var chatTitleCreatorRaw = ChatTitleCreator.foundationModels.rawValue
    @AppStorage("dictationEngine") private var dictationEngine = "apple"
    @AppStorage(ASRPostProcessor.DefaultsKey.enableFragmentRepair) private var enableFragmentRepair = true
    @AppStorage(ASRPostProcessor.DefaultsKey.enableIntentCorrection) private var enableIntentCorrection = true
    @AppStorage(ASRPostProcessor.DefaultsKey.enableRepeatRemoval) private var enableRepeatRemoval = true
    @AppStorage(ASRPostProcessor.DefaultsKey.enableNumberConversion) private var enableNumberConversion = true

    @State private var automationService = AutomationService.shared
    @State private var showAutomationsManager = false
    @State private var parakeetManager = ParakeetModelManager.shared
    @State private var showDeleteConfirmation = false

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

            Section("MCP") {
                SecureField("Linear MCP Token", text: $linearMcpToken)
                    .textFieldStyle(.roundedBorder)

                Text("Used for Linear issue/project tools in the agent sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice & Transcription") {
                Picker("Dictation Engine", selection: $dictationEngine) {
                    Text("Apple Speech").tag("apple")
                    Text("Parakeet TDT v3").tag("parakeet")
                }
                .pickerStyle(.menu)

                Text("Parakeet uses on-device CoreML models for higher accuracy. Apple Speech uses the built-in recognizer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Parakeet model management — only shown when Parakeet is selected.
                if dictationEngine == "parakeet" {
                    GroupBox {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Parakeet Models")
                                    .font(.headline)

                                Text(parakeetManager.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if parakeetManager.areModelsCached {
                                    let sizeMB = Double(parakeetManager.cachedModelSize) / 1_000_000.0
                                    Text(String(format: "%.0f MB on disk", sizeMB))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            if parakeetManager.isLoading {
                                if let progress = parakeetManager.downloadProgress {
                                    VStack(spacing: 4) {
                                        ProgressView(value: progress)
                                            .frame(width: 80)
                                        Text("\(Int(progress * 100))%")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            } else if parakeetManager.isReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)
                            } else {
                                Button("Download") {
                                    Task {
                                        await parakeetManager.downloadAndLoadModels()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)

                        if parakeetManager.areModelsCached && !parakeetManager.isLoading {
                            Divider()
                            HStack {
                                if !parakeetManager.isReady {
                                    Button("Load Models") {
                                        Task {
                                            await parakeetManager.loadModelsFromDisk()
                                        }
                                    }
                                    .controlSize(.small)
                                }

                                Spacer()

                                Button("Delete Models", role: .destructive) {
                                    showDeleteConfirmation = true
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                // Post-processing toggles — shown for all engines since the
                // pipeline runs regardless of which engine produces the transcript.
                GroupBox("Post-Processing") {
                    Toggle("Fragment Repair", isOn: $enableFragmentRepair)
                    Toggle("Intent Correction", isOn: $enableIntentCorrection)
                    Toggle("Repeat Removal", isOn: $enableRepeatRemoval)
                    Toggle("Number Conversion", isOn: $enableNumberConversion)
                }

                Text("Post-processing stages clean up raw transcription output.")
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
        .alert("Delete Parakeet Models?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                parakeetManager.deleteCachedModels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached Parakeet models from disk. You will need to re-download them to use Parakeet transcription.")
        }
    }
}
