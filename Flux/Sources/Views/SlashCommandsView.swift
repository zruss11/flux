import SwiftUI

/// Dropdown list of available slash commands, triggered by typing `/` in the chat input.
struct SlashCommandsView: View {
    @Binding var isPresented: Bool
    @Binding var searchQuery: String
    var workspacePath: String?
    var onCommandSelected: (SlashCommand) -> Void

    @State private var commands: [SlashCommand] = []

    private var filteredCommands: [SlashCommand] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return commands }
        return commands.filter { cmd in
            cmd.name.localizedCaseInsensitiveContains(query)
            || (cmd.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                if filteredCommands.isEmpty {
                    Text(searchQuery.isEmpty ? "No commands available" : "No matching commands")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(filteredCommands) { cmd in
                        commandRow(cmd)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .onAppear {
            loadCommands()
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                loadCommands()
            }
        }
    }

    // MARK: - Row

    private func commandRow(_ cmd: SlashCommand) -> some View {
        Button {
            onCommandSelected(cmd)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cmd.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(colorForSource(cmd.source).opacity(0.85))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("/\(cmd.name)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))

                        Text(cmd.sourceLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(colorForSource(cmd.source).opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(colorForSource(cmd.source).opacity(0.12))
                            )
                    }

                    if let desc = cmd.description {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.0001))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func colorForSource(_ source: SlashCommand.Source) -> Color {
        switch source {
        case .builtIn:  return .cyan
        case .project:  return .green
        case .personal: return .purple
        }
    }

    private func loadCommands() {
        commands = SlashCommandsLoader.loadCommands(workspacePath: workspacePath)
    }
}
