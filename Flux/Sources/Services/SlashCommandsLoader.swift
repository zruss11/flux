import Foundation
import os

/// Discovers slash commands from `.claude/commands/` (project) and `~/.claude/commands/` (personal),
/// plus built-in commands. Follows the Claude Agent SDK convention for custom slash commands.
enum SlashCommandsLoader {

    // MARK: - Public

    /// Load all available slash commands (built-in + filesystem-discovered).
    static func loadCommands(workspacePath: String?) -> [SlashCommand] {
        var commands: [SlashCommand] = SlashCommand.builtIns
        var seen = Set<String>() // dedupe by command name
        for cmd in commands { seen.insert(cmd.name) }

        // Project-scoped commands
        if let ws = workspacePath {
            let projectDir = URL(fileURLWithPath: ws)
                .appendingPathComponent(".claude")
                .appendingPathComponent("commands")
            let projectCmds = discoverCommands(in: projectDir, source: .project)
            for cmd in projectCmds where !seen.contains(cmd.name) {
                commands.append(cmd)
                seen.insert(cmd.name)
            }
        }

        // Personal commands
        let personalDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("commands")
        let personalCmds = discoverCommands(in: personalDir, source: .personal)
        for cmd in personalCmds where !seen.contains(cmd.name) {
            commands.append(cmd)
            seen.insert(cmd.name)
        }

        return commands
    }

    // MARK: - Discovery

    /// Recursively discover `.md` files in the given directory and return SlashCommand instances.
    private static func discoverCommands(in directory: URL, source: SlashCommand.Source) -> [SlashCommand] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            Log.skills.debug("Slash commands dir not found: \(directory.path)")
            return []
        }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.skills.warning("Failed to enumerate: \(directory.path)")
            return []
        }

        var commands: [SlashCommand] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }

            let name = fileURL.deletingPathExtension().lastPathComponent
            guard !name.isEmpty else { continue }

            // Parse YAML frontmatter for description
            let description: String?
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                description = parseFrontmatterDescription(content)
            } else {
                description = nil
            }

            let cmd = SlashCommand(
                id: "\(source.rawValue):\(name)",
                name: name,
                description: description,
                filePath: fileURL.path,
                source: source
            )
            commands.append(cmd)
        }

        Log.skills.debug("Discovered \(commands.count) slash commands in \(directory.lastPathComponent)")
        return commands.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Frontmatter Parser

    /// Extract the `description` value from YAML frontmatter, if present.
    private static func parseFrontmatterDescription(_ markdown: String) -> String? {
        guard markdown.hasPrefix("---\n") else { return nil }

        let searchStart = markdown.index(markdown.startIndex, offsetBy: 4)
        guard let endRange = markdown.range(of: "\n---", range: searchStart..<markdown.endIndex) else { return nil }

        let yamlBlock = String(markdown[searchStart..<endRange.lowerBound])

        for line in yamlBlock.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("description:") {
                let value = String(trimmed.dropFirst("description:".count))
                    .trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    return String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
