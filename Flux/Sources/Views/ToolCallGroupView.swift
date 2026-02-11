import SwiftUI

// MARK: - Tool Call Group View

/// Collapsible group showing "N Called Tools" with expand/collapse to reveal individual tool calls.
struct ToolCallGroupView: View {
    let calls: [ToolCallInfo]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: chevron + badge + "Called Tools"
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 14)

                    // Numbered badge
                    Text("\(calls.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.12))
                        )

                    Text("Called Tools")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    // Spinner if any tools are still pending
                    if calls.contains(where: { $0.status == .pending }) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .buttonStyle(.plain)

            // Expanded: list individual tool calls
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(calls) { call in
                        ToolCallRow(call: call)
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Individual Tool Call Row

/// A single tool call row that can be expanded to show the result preview.
struct ToolCallRow: View {
    let call: ToolCallInfo
    @State private var isExpanded = false

    /// Human-readable display name for common tool names
    private var displayName: String {
        switch call.toolName {
        case "capture_screen": return "Capture screen"
        case "read_ax_tree": return "Read accessibility tree"
        case "read_selected_text": return "Read selected text"
        case "execute_applescript": return "AppleScript"
        case "run_shell_command": return "Shell command"
        case "send_slack_message": return "Send Slack message"
        case "send_discord_message": return "Send Discord message"
        default:
            // Convert snake_case to Title Case, handle MCP-style names (e.g. linear__list_issues)
            return call.toolName
                .replacingOccurrences(of: "__", with: " → ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if call.resultPreview != nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // Status indicator
                    Group {
                        if call.status == .pending {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        } else if call.resultPreview != nil {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.green.opacity(0.7))
                        }
                    }
                    .frame(width: 14)

                    Text(displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))

                    if !call.inputSummary.isEmpty && call.inputSummary != call.toolName {
                        Text(call.inputSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.0001)) // hit target
                )
            }
            .buttonStyle(.plain)

            // Expanded: show result preview
            if isExpanded, let preview = call.resultPreview {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.04))
                    )
                    .padding(.leading, 14)
                    .transition(.opacity)
            }
        }
    }
}
