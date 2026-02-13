import Foundation

/// Represents a single slash command discovered from the filesystem or built-in.
struct SlashCommand: Identifiable, Hashable {
    let id: String          // unique key, e.g. "project:refactor" or "builtin:new"
    let name: String        // command name without leading `/`
    let description: String?
    let filePath: String?   // nil for built-in commands
    let source: Source

    enum Source: String, Hashable {
        case project   // .claude/commands/ in workspace
        case personal  // ~/.claude/commands/
        case builtIn   // hard-coded commands like /new
    }

    /// Display label shown in the source badge
    var sourceLabel: String {
        switch source {
        case .project:  return "project"
        case .personal: return "personal"
        case .builtIn:  return "built-in"
        }
    }

    /// SF Symbol icon for this command
    var icon: String {
        switch source {
        case .builtIn:  return "terminal.fill"
        case .project:  return "folder.fill"
        case .personal: return "person.fill"
        }
    }

    // MARK: - Built-in Commands

    static let builtIns: [SlashCommand] = [
        SlashCommand(
            id: "builtin:new",
            name: "new",
            description: "Start a new conversation",
            filePath: nil,
            source: .builtIn
        ),
        SlashCommand(
            id: "builtin:clear",
            name: "clear",
            description: "Clear conversation and start fresh",
            filePath: nil,
            source: .builtIn
        ),
        SlashCommand(
            id: "builtin:compact",
            name: "compact",
            description: "Summarize conversation to reduce token usage",
            filePath: nil,
            source: .builtIn
        ),
        SlashCommand(
            id: "builtin:help",
            name: "help",
            description: "Show available commands and usage tips",
            filePath: nil,
            source: .builtIn
        ),
        SlashCommand(
            id: "builtin:cost",
            name: "cost",
            description: "Show token usage and estimated cost for this session",
            filePath: nil,
            source: .builtIn
        ),
    ]
}
