import Foundation
import AppKit

@MainActor
final class ToolRunner {
    private let contextManager = ContextManager()

    func executeTool(_ tool: CustomTool, context: ScreenContext) async -> String {
        var prompt = tool.prompt

        // Resolve template variables
        for variable in tool.variables {
            let placeholder = "{{\(variable.rawValue)}}"
            let value: String
            switch variable {
            case .screen:
                if let tree = context.axTree {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    value = (try? String(data: encoder.encode(tree), encoding: .utf8)) ?? "No screen data"
                } else {
                    value = "No screen data available"
                }
            case .clipboard:
                value = NSPasteboard.general.string(forType: .string) ?? "Clipboard empty"
            case .selectedText:
                value = context.selectedText ?? "No text selected"
            }
            prompt = prompt.replacingOccurrences(of: placeholder, with: value)
        }

        // Execute actions sequentially
        var results: [String] = []
        for action in tool.actions {
            let result = await executeAction(action)
            results.append(result)
        }

        return results.joined(separator: "\n")
    }

    private func executeAction(_ action: ToolAction) async -> String {
        switch action {
        case .shortcut(let name):
            return await executeShortcut(named: name)
        case .shell(let script):
            return await executeShellScript(script)
        case .applescript(let script):
            return executeAppleScript(script)
        case .claude(let instructions):
            return "Claude action: \(instructions)"
        }
    }

    func executeShortcut(named name: String) async -> String {
        await executeShellScript("/usr/bin/shortcuts run \"\(name)\"")
    }

    func executeShellScript(_ script: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executeAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)

        if let error {
            return "AppleScript error: \(error)"
        }

        return result?.stringValue ?? ""
    }
}
