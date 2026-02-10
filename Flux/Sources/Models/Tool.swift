import Foundation

struct CustomTool: Codable, Identifiable {
    var id = UUID()
    var name: String
    var icon: String
    var description: String
    var prompt: String
    var variables: [ContextVariable]
    var actions: [ToolAction]
    var trigger: ToolTrigger?

    enum ContextVariable: String, Codable, CaseIterable, Sendable {
        case screen
        case clipboard
        case selectedText = "selected_text"
    }
}

enum ToolAction: Codable, Sendable {
    case shortcut(name: String)
    case shell(script: String)
    case applescript(script: String)
    case claude(instructions: String)

    private enum CodingKeys: String, CodingKey {
        case type, name, script, instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "shortcut":
            self = .shortcut(name: try container.decode(String.self, forKey: .name))
        case "shell":
            self = .shell(script: try container.decode(String.self, forKey: .script))
        case "applescript":
            self = .applescript(script: try container.decode(String.self, forKey: .script))
        case "claude":
            self = .claude(instructions: try container.decode(String.self, forKey: .instructions))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shortcut(let name):
            try container.encode("shortcut", forKey: .type)
            try container.encode(name, forKey: .name)
        case .shell(let script):
            try container.encode("shell", forKey: .type)
            try container.encode(script, forKey: .script)
        case .applescript(let script):
            try container.encode("applescript", forKey: .type)
            try container.encode(script, forKey: .script)
        case .claude(let instructions):
            try container.encode("claude", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
        }
    }
}

struct ToolTrigger: Codable, Sendable {
    var type: TriggerType
    var keys: String

    enum TriggerType: String, Codable, Sendable {
        case hotkey
    }
}
