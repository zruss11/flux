import Foundation
import SwiftUI

// MARK: - Tool Call Info

struct ToolCallInfo: Identifiable {
    let id: String          // toolUseId from the agent
    let toolName: String
    let inputSummary: String
    var status: ToolCallStatus = .pending
    var resultPreview: String?

    enum ToolCallStatus {
        case pending
        case complete
    }
}

// MARK: - Display Segments

/// A display-oriented view of the conversation that groups consecutive tool calls
/// and separates assistant text into distinct visual segments.
enum DisplaySegment: Identifiable {
    case userMessage(Message)
    case assistantText(Message)
    case toolCallGroup(id: String, calls: [ToolCallInfo])

    var id: String {
        switch self {
        case .userMessage(let m): return "user-\(m.id)"
        case .assistantText(let m): return "text-\(m.id)"
        case .toolCallGroup(let id, _): return "tools-\(id)"
        }
    }
}

// MARK: - Conversation Store

@Observable
final class ConversationStore {
    var conversations: [Conversation] = []
    var activeConversationId: UUID?

    var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationId }
    }

    func createConversation() -> Conversation {
        let conversation = Conversation()
        conversations.append(conversation)
        activeConversationId = conversation.id
        return conversation
    }

    func addMessage(to conversationId: UUID, role: Message.Role, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let message = Message(role: role, content: content)
        conversations[index].messages.append(message)
    }

    func updateLastAssistantMessage(in conversationId: UUID, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
              let lastIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[index].messages[lastIndex].content = content
    }

    func appendToLastAssistantMessage(in conversationId: UUID, chunk: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
              let lastIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[index].messages[lastIndex].content.append(chunk)
    }

    // MARK: - Tool Call Tracking

    /// Adds a tool call to the last assistant message, or creates a new assistant message if the
    /// last message isn't from the assistant.
    func addToolCall(to conversationId: UUID, info: ToolCallInfo) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].toolCalls.append(info)
        } else {
            // No assistant message yet for this turn — create one with empty text
            var message = Message(role: .assistant, content: "")
            message.toolCalls.append(info)
            conversations[index].messages.append(message)
        }
    }

    /// Marks a tool call as complete and attaches a result preview.
    func completeToolCall(in conversationId: UUID, toolUseId: String, resultPreview: String?) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        // Search backward for the message containing this tool call
        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let tcIndex = conversations[convIndex].messages[msgIndex].toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                conversations[convIndex].messages[msgIndex].toolCalls[tcIndex].status = .complete
                conversations[convIndex].messages[msgIndex].toolCalls[tcIndex].resultPreview = resultPreview
                return
            }
        }
    }
}

// MARK: - Conversation

struct Conversation: Identifiable {
    let id = UUID()
    var messages: [Message] = []
    let createdAt = Date()

    /// Produces display segments for the chat view by grouping tool calls and
    /// separating them from assistant text content.
    var displaySegments: [DisplaySegment] {
        var segments: [DisplaySegment] = []

        for message in messages {
            switch message.role {
            case .user:
                segments.append(.userMessage(message))
            case .assistant:
                // If the message has text content, emit a text segment
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(.assistantText(message))
                }
                // If the message has tool calls, emit a tool call group
                if !message.toolCalls.isEmpty {
                    segments.append(.toolCallGroup(id: message.id.uuidString, calls: message.toolCalls))
                }
            case .system:
                // System messages render like assistant text
                segments.append(.assistantText(message))
            }
        }

        return segments
    }
}

// MARK: - Message

struct Message: Identifiable {
    let id = UUID()
    var role: Role
    var content: String
    var toolCalls: [ToolCallInfo] = []
    let timestamp = Date()

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }
}
