import Foundation
import SwiftUI

// MARK: - Tool Call Info

struct ToolCallInfo: Identifiable, Codable {
    let id: String          // toolUseId from the agent
    let toolName: String
    let inputSummary: String
    var status: ToolCallStatus = .pending
    var resultPreview: String?

    enum ToolCallStatus: String, Codable {
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

@MainActor
@Observable
final class ConversationStore {
    /// Test-only override for history persistence location.
    /// Kept in all build configurations so release test runs can compile.
    static var overrideHistoryDirectory: URL?
    var conversations: [Conversation] = []
    var activeConversationId: UUID?
    var folders: [ChatFolder] = []
    var summaries: [ConversationSummary] = []
    var workspacePath: String? {
        didSet { UserDefaults.standard.set(workspacePath, forKey: "workspacePath") }
    }
    var activeWorktreeBranch: String?
    private var runningConversationIds: Set<UUID> = []
    private(set) var scrollRevision: Int = 0
    private(set) var lastScrollConversationId: UUID?

    // MARK: - Persistence Paths

    private static var historyDirectory: URL {
        if let overrideHistoryDirectory {
            return overrideHistoryDirectory
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".flux/history", isDirectory: true)
    }

    private static var conversationsDirectory: URL {
        historyDirectory.appendingPathComponent("conversations", isDirectory: true)
    }

    private static var indexURL: URL {
        historyDirectory.appendingPathComponent("index.json")
    }

    var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationId }
    }

    var hasRunningConversations: Bool {
        !runningConversationIds.isEmpty
    }

    // MARK: - Lifecycle

    init() {
        workspacePath = UserDefaults.standard.string(forKey: "workspacePath")
        loadIndex()
    }

    // MARK: - Conversation CRUD

    func createConversation() -> Conversation {
        let conversation = Conversation()
        conversations.append(conversation)
        activeConversationId = conversation.id

        let summary = ConversationSummary(
            id: conversation.id,
            title: "New Chat",
            createdAt: conversation.createdAt,
            lastMessageAt: conversation.createdAt,
            messageCount: 0,
            folderId: nil
        )
        summaries.insert(summary, at: 0)
        saveIndex()
        return conversation
    }

    @discardableResult
    func ensureConversationExists(id: UUID, title: String, activate: Bool = false) -> Conversation {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            let conversation = conversations[index]
            let changed = ensureSummaryExists(for: conversation, title: title)
            if activate {
                activeConversationId = id
            }
            if changed {
                saveIndex()
            }
            return conversation
        }

        if let loaded = loadConversation(id: id) {
            conversations.append(loaded)
            let changed = ensureSummaryExists(for: loaded, title: title)
            if activate {
                activeConversationId = id
            }
            if changed {
                saveIndex()
            }
            return loaded
        }

        let conversation = Conversation(id: id)
        conversations.append(conversation)
        _ = ensureSummaryExists(for: conversation, title: title)
        saveConversation(conversation)
        saveIndex()
        if activate {
            activeConversationId = id
        }
        return conversation
    }

    func addMessage(
        to conversationId: UUID,
        role: Message.Role,
        content: String,
        imageAttachments: [MessageImageAttachment] = []
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let message = Message(role: role, content: content, imageAttachments: imageAttachments)
        conversations[index].messages.append(message)

        // Update summary
        if let si = summaries.firstIndex(where: { $0.id == conversationId }) {
            summaries[si].lastMessageAt = message.timestamp
            summaries[si].messageCount = conversations[index].messages.count

            // Auto-title from first user message.
            // We set an immediate fallback title for snappy UI, then (optionally) refine it asynchronously.
            if summaries[si].title == "New Chat" && role == .user {
                let fallbackTitle = ChatTitleService.truncatedTitle(from: content)
                summaries[si].title = fallbackTitle

                let messageSnapshot = content
                let conversationIdSnapshot = conversationId
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let proposed = await ChatTitleService.shared.proposeTitle(fromFirstUserMessage: messageSnapshot) else { return }

                    guard let si2 = self.summaries.firstIndex(where: { $0.id == conversationIdSnapshot }) else { return }
                    // Don't clobber user edits. Only replace the title if it hasn't changed since we set the fallback.
                    guard self.summaries[si2].title == fallbackTitle else { return }

                    self.summaries[si2].title = proposed
                    self.saveIndex()
                }
            }
        }

        saveConversation(conversations[index])
        saveIndex()
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    func updateLastAssistantMessage(in conversationId: UUID, content: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
              let lastIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[index].messages[lastIndex].content = content
        debouncedSave(conversations[index])
    }

    func appendToLastAssistantMessage(in conversationId: UUID, chunk: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }),
              let lastIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        conversations[index].messages[lastIndex].content.append(chunk)
        debouncedSave(conversations[index])
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    // MARK: - Tool Call Tracking

    func addToolCall(to conversationId: UUID, info: ToolCallInfo) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].toolCalls.append(info)
        } else {
            var message = Message(role: .assistant, content: "")
            message.toolCalls.append(info)
            conversations[index].messages.append(message)
        }
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    func completeToolCall(in conversationId: UUID, toolUseId: String, resultPreview: String?) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let tcIndex = conversations[convIndex].messages[msgIndex].toolCalls.firstIndex(where: { $0.id == toolUseId }) {
                conversations[convIndex].messages[msgIndex].toolCalls[tcIndex].status = .complete
                conversations[convIndex].messages[msgIndex].toolCalls[tcIndex].resultPreview = resultPreview
                saveConversation(conversations[convIndex])
                lastScrollConversationId = conversationId
                scrollRevision &+= 1
                return
            }
        }
    }

    // MARK: - History Management

    /// Load a conversation from disk into memory and set it as active.
    func openConversation(id: UUID) {
        if let existing = conversations.first(where: { $0.id == id }) {
            activeConversationId = existing.id
            return
        }
        if let loaded = loadConversation(id: id) {
            conversations.append(loaded)
            activeConversationId = loaded.id
        }
    }

    /// Start a fresh conversation (from the history view).
    func startNewConversation() {
        _ = createConversation()
    }

    func deleteConversation(id: UUID) {
        conversations.removeAll { $0.id == id }
        summaries.removeAll { $0.id == id }
        runningConversationIds.remove(id)
        // Remove from any folder
        for i in folders.indices {
            folders[i].conversationIds.removeAll { $0 == id }
        }
        if activeConversationId == id {
            activeConversationId = nil
        }
        // Delete file
        let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        saveIndex()
    }

    func renameConversation(id: UUID, to newTitle: String) {
        if let si = summaries.firstIndex(where: { $0.id == id }) {
            summaries[si].title = newTitle
            saveIndex()
        }
    }

    /// Fork an existing conversation: duplicate its messages into a brand-new
    /// conversation and return the new ID. The caller is responsible for
    /// notifying the sidecar via `AgentBridge.sendForkConversation`.
    @discardableResult
    func forkConversation(id: UUID) -> UUID? {
        // Load the source conversation if it isn't already in memory.
        let source: Conversation
        if let existing = conversations.first(where: { $0.id == id }) {
            source = existing
        } else if let loaded = loadConversation(id: id) {
            source = loaded
        } else {
            return nil
        }

        let newConversation = Conversation(messages: source.messages)
        conversations.append(newConversation)
        activeConversationId = newConversation.id

        // Build a title for the fork.
        let sourceTitle = summaries.first(where: { $0.id == id })?.title ?? "Chat"
        let forkTitle = "Fork of \(sourceTitle)"

        let summary = ConversationSummary(
            id: newConversation.id,
            title: forkTitle,
            createdAt: newConversation.createdAt,
            lastMessageAt: source.messages.last?.timestamp ?? newConversation.createdAt,
            messageCount: newConversation.messages.count,
            folderId: nil
        )
        summaries.insert(summary, at: 0)
        saveConversation(newConversation)
        saveIndex()

        return newConversation.id
    }
    // MARK: - Folder Management

    @discardableResult
    func createFolder(name: String) -> ChatFolder {
        let folder = ChatFolder(name: name)
        folders.append(folder)
        saveIndex()
        return folder
    }

    func renameFolder(id: UUID, to newName: String) {
        if let i = folders.firstIndex(where: { $0.id == id }) {
            folders[i].name = newName
            saveIndex()
        }
    }

    func deleteFolder(id: UUID) {
        // Move conversations back to unfiled
        if let fi = folders.firstIndex(where: { $0.id == id }) {
            for convId in folders[fi].conversationIds {
                if let si = summaries.firstIndex(where: { $0.id == convId }) {
                    summaries[si].folderId = nil
                }
            }
            folders.remove(at: fi)
            saveIndex()
        }
    }

    func moveConversation(_ conversationId: UUID, toFolder folderId: UUID?) {
        // Remove from old folder
        for i in folders.indices {
            folders[i].conversationIds.removeAll { $0 == conversationId }
        }
        // Add to new folder
        if let folderId, let fi = folders.firstIndex(where: { $0.id == folderId }) {
            folders[fi].conversationIds.append(conversationId)
        }
        // Update summary
        if let si = summaries.firstIndex(where: { $0.id == conversationId }) {
            summaries[si].folderId = folderId
        }
        saveIndex()
    }

    // MARK: - Run State

    func setConversationRunning(_ conversationId: UUID, isRunning: Bool) {
        if isRunning {
            runningConversationIds.insert(conversationId)
        } else {
            runningConversationIds.remove(conversationId)
        }
    }

    /// Conversations not assigned to any folder, sorted by recency.
    var unfiledSummaries: [ConversationSummary] {
        summaries
            .filter { $0.folderId == nil }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Summaries for a given folder, ordered as stored.
    func summaries(forFolder folderId: UUID) -> [ConversationSummary] {
        guard let folder = folders.first(where: { $0.id == folderId }) else { return [] }
        return folder.conversationIds.compactMap { cid in
            summaries.first { $0.id == cid }
        }
    }

    // MARK: - Persistence

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.conversationsDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    private func ensureSummaryExists(for conversation: Conversation, title: String) -> Bool {
        if let index = summaries.firstIndex(where: { $0.id == conversation.id }) {
            if summaries[index].title == "New Chat",
               summaries[index].messageCount == 0,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summaries[index].title = title
                return true
            }
            return false
        }

        let fallbackTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = fallbackTitle.isEmpty ? "New Chat" : fallbackTitle
        let lastMessageAt = conversation.messages.last?.timestamp ?? conversation.createdAt
        let summary = ConversationSummary(
            id: conversation.id,
            title: resolvedTitle,
            createdAt: conversation.createdAt,
            lastMessageAt: lastMessageAt,
            messageCount: conversation.messages.count,
            folderId: nil
        )
        summaries.insert(summary, at: 0)
        return true
    }

    private func saveConversation(_ conversation: Conversation) {
        ensureDirectories()
        let url = Self.conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private var saveTimer: Timer?

    /// Debounce saves during streaming to avoid excessive disk writes.
    private func debouncedSave(_ conversation: Conversation) {
        saveTimer?.invalidate()
        let convCopy = conversation
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveConversation(convCopy)
            self?.saveIndex()
        }
    }

    private func loadConversation(id: UUID) -> Conversation? {
        let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Conversation.self, from: data)
    }

    private struct HistoryIndex: Codable {
        var summaries: [ConversationSummary]
        var folders: [ChatFolder]
    }

    private func saveIndex() {
        ensureDirectories()
        let index = HistoryIndex(summaries: summaries, folders: folders)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(index) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let index = try? decoder.decode(HistoryIndex.self, from: data) {
            summaries = index.summaries
            folders = index.folders
        }
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [Message]
    let createdAt: Date

    init(id: UUID = UUID(), messages: [Message] = [], createdAt: Date = Date()) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
    }

    /// Produces display segments for the chat view by grouping tool calls and
    /// separating them from assistant text content.
    var displaySegments: [DisplaySegment] {
        var segments: [DisplaySegment] = []

        for message in messages {
            switch message.role {
            case .user:
                segments.append(.userMessage(message))
            case .assistant:
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(.assistantText(message))
                }
                if !message.toolCalls.isEmpty {
                    segments.append(.toolCallGroup(id: message.id.uuidString, calls: message.toolCalls))
                }
            case .system:
                segments.append(.assistantText(message))
            }
        }

        return segments
    }
}

// MARK: - Message

struct Message: Identifiable, Codable {
    let id: UUID
    var role: Role
    var content: String
    var imageAttachments: [MessageImageAttachment]
    var toolCalls: [ToolCallInfo]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        imageAttachments: [MessageImageAttachment] = [],
        toolCalls: [ToolCallInfo] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageAttachments = imageAttachments
        self.toolCalls = toolCalls
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case imageAttachments
        case toolCalls
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        imageAttachments = try container.decodeIfPresent([MessageImageAttachment].self, forKey: .imageAttachments) ?? []
        toolCalls = try container.decodeIfPresent([ToolCallInfo].self, forKey: .toolCalls) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(imageAttachments, forKey: .imageAttachments)
        try container.encode(toolCalls, forKey: .toolCalls)
        try container.encode(timestamp, forKey: .timestamp)
    }

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }
}

struct MessageImageAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let mediaType: String
    let base64Data: String

    init(id: UUID = UUID(), fileName: String, mediaType: String, base64Data: String) {
        self.id = id
        self.fileName = fileName
        self.mediaType = mediaType
        self.base64Data = base64Data
    }
}
