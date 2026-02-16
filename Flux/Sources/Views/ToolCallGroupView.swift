import AppKit
import SwiftUI

// MARK: - Tool Icon Mapping

private struct ToolKindVisual: Identifiable, Hashable {
    let id: String
    let label: String
    let symbolName: String
    let tint: Color
    let customAssetNames: [String]

    static func from(toolName rawToolName: String) -> ToolKindVisual {
        let toolName = rawToolName.lowercased()

        // MCP tool format: <serverId>__<toolName>
        if let split = toolName.firstRange(of: "__") {
            let serverId = String(toolName[..<split.lowerBound])
            return visualForServer(id: serverId)
        }

        if toolName == "run_shell_command" || toolName.contains("shell") || toolName.contains("bash") || toolName.contains("terminal") {
            return ToolKindVisual(
                id: "terminal",
                label: "Terminal",
                symbolName: "apple.terminal",
                tint: .orange,
                customAssetNames: []
            )
        }

        if toolName == "read_file" {
            return ToolKindVisual(
                id: "file",
                label: "File",
                symbolName: "doc.text",
                tint: .indigo,
                customAssetNames: []
            )
        }

        if toolName.hasPrefix("calendar_") {
            return ToolKindVisual(
                id: "calendar",
                label: "Calendar",
                symbolName: "calendar",
                tint: .red,
                customAssetNames: []
            )
        }

        if toolName.hasPrefix("imessage_") {
            return ToolKindVisual(
                id: "messages",
                label: "Messages",
                symbolName: "message.fill",
                tint: .green,
                customAssetNames: []
            )
        }

        if toolName.hasPrefix("linear_") || toolName == "linear__setup" || toolName == "linear__mcp_list_tools" {
            return visualForServer(id: "linear")
        }

        if toolName == "check_github_status" || toolName == "manage_github_repos" || toolName.hasPrefix("github_") {
            return visualForServer(id: "github")
        }

        if toolName.hasSuffix("automation") || toolName.contains("automation") {
            return ToolKindVisual(
                id: "automation",
                label: "Automation",
                symbolName: "clock.arrow.2.circlepath",
                tint: .mint,
                customAssetNames: []
            )
        }

        if toolName == "capture_screen" || toolName == "read_visible_windows" || toolName == "read_ax_tree" {
            return ToolKindVisual(
                id: "screen",
                label: "Screen",
                symbolName: "display",
                tint: .cyan,
                customAssetNames: []
            )
        }

        if toolName == "read_selected_text" {
            return ToolKindVisual(
                id: "selection",
                label: "Selected text",
                symbolName: "character.cursor.ibeam",
                tint: .teal,
                customAssetNames: []
            )
        }

        if toolName == "read_clipboard_history" {
            return ToolKindVisual(
                id: "clipboard",
                label: "Clipboard",
                symbolName: "doc.on.clipboard",
                tint: .purple,
                customAssetNames: []
            )
        }

        if toolName == "read_session_history" || toolName == "get_session_context_summary" {
            return ToolKindVisual(
                id: "session",
                label: "Session",
                symbolName: "clock.arrow.circlepath",
                tint: .blue,
                customAssetNames: []
            )
        }

        if toolName == "delegate_to_agent" {
            return ToolKindVisual(
                id: "delegate",
                label: "Delegate",
                symbolName: "person.2.fill",
                tint: .green,
                customAssetNames: []
            )
        }

        if toolName == "get_current_datetime" {
            return ToolKindVisual(
                id: "datetime",
                label: "Date/Time",
                symbolName: "clock",
                tint: .gray,
                customAssetNames: []
            )
        }

        if toolName == "set_worktree" {
            return ToolKindVisual(
                id: "git",
                label: "Git",
                symbolName: "arrow.triangle.branch",
                tint: .brown,
                customAssetNames: []
            )
        }

        return ToolKindVisual(
            id: "generic",
            label: "Tool",
            symbolName: "wrench.and.screwdriver",
            tint: .gray,
            customAssetNames: []
        )
    }

    private static func visualForServer(id serverId: String) -> ToolKindVisual {
        switch serverId {
        case "linear":
            return ToolKindVisual(
                id: "linear",
                label: "Linear",
                symbolName: "line.3.horizontal.decrease.circle",
                tint: .white,
                customAssetNames: ["tool-linear", "linear"]
            )
        case "notion":
            return ToolKindVisual(
                id: "notion",
                label: "Notion",
                symbolName: "note.text",
                tint: .white,
                customAssetNames: ["tool-notion", "notion"]
            )
        case "github":
            return ToolKindVisual(
                id: "github",
                label: "GitHub",
                symbolName: "chevron.left.forwardslash.chevron.right",
                tint: .white,
                customAssetNames: ["tool-github", "github"]
            )
        case "calendar":
            return ToolKindVisual(
                id: "calendar",
                label: "Calendar",
                symbolName: "calendar",
                tint: .red,
                customAssetNames: []
            )
        default:
            return ToolKindVisual(
                id: "mcp:\(serverId)",
                label: serverId.capitalized,
                symbolName: "puzzlepiece.extension",
                tint: .gray,
                customAssetNames: []
            )
        }
    }
}

private struct ToolKindIconStack: View {
    let kinds: [ToolKindVisual]
    private let maxVisible = 5

    var body: some View {
        let visible = Array(kinds.prefix(maxVisible))
        let remaining = max(kinds.count - maxVisible, 0)

        HStack(spacing: -6) {
            ForEach(visible) { kind in
                iconBubble(kind: kind)
            }

            if remaining > 0 {
                Text("+\(remaining)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .circular)
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        Capsule(style: .circular)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    )
                    .padding(.leading, 4)
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private func iconBubble(kind: ToolKindVisual) -> some View {
        let custom = kind.customAssetNames.compactMap(Self.loadCustomAsset(named:)).first

        ZStack {
            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )

            if let custom {
                Image(nsImage: custom)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(kind.tint.opacity(0.95))
            }
        }
        .help(kind.label)
    }

    private static func loadCustomAsset(named name: String) -> NSImage? {
        let exts = ["pdf", "png", "jpg", "jpeg", "webp"]
        for ext in exts {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "ToolIcons"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

// MARK: - Tool Call Group View

/// Collapsible group showing "N Called Tools" with expand/collapse to reveal individual tool calls.
struct ToolCallGroupView: View {
    let calls: [ToolCallInfo]
    @State private var isExpanded = false

    private var uniqueToolKinds: [ToolKindVisual] {
        var seen = Set<String>()
        var ordered: [ToolKindVisual] = []

        for call in calls {
            let visual = ToolKindVisual.from(toolName: call.toolName)
            if seen.insert(visual.id).inserted {
                ordered.append(visual)
            }
        }

        return ordered
    }

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

                    if !uniqueToolKinds.isEmpty {
                        ToolKindIconStack(kinds: uniqueToolKinds)
                    }

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
        case "read_visible_windows": return "Read visible windows"
        case "read_selected_text": return "Read selected text"
        case "read_file": return "Read file"
        case "run_shell_command": return "Run shell command"
        case "create_automation": return "Create automation"
        case "list_automations": return "List automations"
        case "update_automation": return "Update automation"
        case "pause_automation": return "Pause automation"
        case "resume_automation": return "Resume automation"
        case "delete_automation": return "Delete automation"
        case "run_automation_now": return "Run automation now"
        case "memory": return "Memory"
        case "calendar_search_events": return "Search Events"
        case "calendar_add_event": return "Add Event"
        case "calendar_edit_event": return "Edit Event"
        case "calendar_delete_event": return "Delete Event"
        case "calendar_navigate_to_date": return "Navigate to Date"
        case "imessage_list_accounts": return "List Message Accounts"
        case "imessage_list_chats": return "List Message Chats"
        case "imessage_send_message": return "Send Message"
        case "get_current_datetime": return "Get Date/Time"
        case "delegate_to_agent": return "Delegate to Agent"
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
