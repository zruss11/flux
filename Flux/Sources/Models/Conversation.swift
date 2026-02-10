import Foundation
import SwiftUI

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
}

struct Conversation: Identifiable {
    let id = UUID()
    var messages: [Message] = []
    let createdAt = Date()
}

struct Message: Identifiable {
    let id = UUID()
    var role: Role
    var content: String
    let timestamp = Date()

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }
}
