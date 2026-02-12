import SwiftUI

/// Settings panel for managing per-app AI custom instructions.
///
/// Allows users to add, edit, and remove instructions that change the AI's
/// behavior based on which application is currently in the foreground.
struct AppInstructionsView: View {
    @State private var instructions: [AppInstructions.Instruction] = []
    @State private var draftBundleId = ""
    @State private var draftAppName = ""
    @State private var draftInstruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-App AI Instructions")
                .font(.headline)

            Text("Customize how the AI behaves when you're using each app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if instructions.isEmpty {
                Text("No per-app instructions configured.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(instructions) { instruction in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instruction.appName)
                                .font(.subheadline.bold())
                            Text(instruction.bundleId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(instruction.instruction)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            remove(id: instruction.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }

            GroupBox("Add New") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("App Name", text: $draftAppName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                        TextField("Bundle ID", text: $draftBundleId)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Instruction (e.g. \"Be casual, use emoji\")", text: $draftInstruction)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()

                        if let current = AppMonitor.shared.currentApp {
                            Button("Use Current App") {
                                draftAppName = current.appName
                                draftBundleId = current.bundleId
                            }
                            .font(.caption)
                            .help("Autofill with the currently active app: \(current.appName)")
                        }

                        Button("Add") {
                            addInstruction()
                        }
                        .disabled(draftBundleId.isEmpty || draftInstruction.isEmpty)
                    }
                }
                .padding(4)
            }
        }
        .padding()
        .onAppear { reload() }
    }

    private func reload() {
        instructions = AppInstructions.shared.instructions
    }

    private func addInstruction() {
        let name = draftAppName.isEmpty ? draftBundleId : draftAppName
        AppInstructions.shared.upsert(
            .init(bundleId: draftBundleId, appName: name, instruction: draftInstruction)
        )
        draftBundleId = ""
        draftAppName = ""
        draftInstruction = ""
        reload()
    }

    private func remove(id: String) {
        AppInstructions.shared.remove(id: id)
        reload()
    }
}
