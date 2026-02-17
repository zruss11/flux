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

// MARK: - Pending Permission Request

struct PendingPermissionRequest: Identifiable, Codable {
    let id: String          // requestId from the sidecar
    let toolName: String
    let input: [String: String]  // simplified key-value for display
    var status: PermissionStatus = .pending

    enum PermissionStatus: String, Codable {
        case pending
        case approved
        case denied
    }
}

// MARK: - Pending Ask User Question

struct PendingAskUserQuestion: Identifiable, Codable {
    let id: String          // requestId from the sidecar
    let questions: [Question]
    var answers: [String: String] = [:]
    var status: PermissionStatus = .pending

    struct Question: Codable, Identifiable {
        let id: UUID
        let question: String
        let options: [Option]
        let multiSelect: Bool

        init(id: UUID = UUID(), question: String, options: [Option], multiSelect: Bool) {
            self.id = id
            self.question = question
            self.options = options
            self.multiSelect = multiSelect
        }

        enum CodingKeys: String, CodingKey {
            case id
            case question
            case options
            case multiSelect
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            question = try container.decode(String.self, forKey: .question)
            options = try container.decode([Option].self, forKey: .options)
            multiSelect = try container.decode(Bool.self, forKey: .multiSelect)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(question, forKey: .question)
            try container.encode(options, forKey: .options)
            try container.encode(multiSelect, forKey: .multiSelect)
        }

        struct Option: Codable, Identifiable {
            let id: UUID
            let label: String
            let description: String?

            init(id: UUID = UUID(), label: String, description: String?) {
                self.id = id
                self.label = label
                self.description = description
            }

            enum CodingKeys: String, CodingKey {
                case id
                case label
                case description
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
                label = try container.decode(String.self, forKey: .label)
                description = try container.decodeIfPresent(String.self, forKey: .description)
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(label, forKey: .label)
                try container.encodeIfPresent(description, forKey: .description)
            }
        }
    }

    enum PermissionStatus: String, Codable {
        case pending
        case answered
    }
}

// MARK: - Sub-Agent Activity

struct SubAgentActivity: Identifiable, Codable {
    let id: String        // toolUseId (parent delegate_to_agent call)
    let agentId: String
    let agentName: String
    var toolCalls: [ToolCallInfo]
    var status: Status
    var resultPreview: String?

    enum Status: String, Codable {
        case running
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
    case permissionRequest(PendingPermissionRequest)
    case askUserQuestion(PendingAskUserQuestion)
    case subAgentGroup(SubAgentActivity)

    var id: String {
        switch self {
        case .userMessage(let m): return "user-\(m.id)"
        case .assistantText(let m): return "text-\(m.id)"
        case .toolCallGroup(let id, _): return "tools-\(id)"
        case .permissionRequest(let req): return "perm-\(req.id)"
        case .askUserQuestion(let q): return "ask-\(q.id)"
        case .subAgentGroup(let a): return "agent-\(a.id)"
        }
    }
}

// MARK: - Conversation Store

@MainActor
@Observable
final class ConversationStore {
    /// Test-only override for history persistence location.
    /// Kept in all build configurations so release test runs can compile.
    nonisolated(unsafe) static var overrideHistoryDirectory: URL?
    var conversations: [Conversation] = []
    var activeConversationId: UUID?
    var folders: [ChatFolder] = []
    var summaries: [ConversationSummary] = []
    var workspacePath: String? {
        didSet {
            UserDefaults.standard.set(workspacePath, forKey: "workspacePath")
            recordRecentWorkspacePath(workspacePath)
        }
    }
    private(set) var recentWorkspacePaths: [String] = []
    var activeWorktreeBranch: String?
    private(set) var worktreeTaskTitlesByBranch: [String: String] = [:]
    private(set) var worktreeConversationIdsByBranch: [String: String] = [:]
    private var runningConversationIds: Set<UUID> = []
    private var loadingConversationIds: Set<UUID> = []
    /// Conversation IDs that finished running but haven't been viewed yet.
    private(set) var unreadReadyConversationIds: Set<UUID> = []
    private(set) var scrollRevision: Int = 0
    private(set) var lastScrollConversationId: UUID?

    // MARK: - Persistence Paths

    private static nonisolated var historyDirectory: URL {
        if let override = overrideHistoryDirectory {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".flux/history", isDirectory: true)
    }

    private static nonisolated var conversationsDirectory: URL {
        historyDirectory.appendingPathComponent("conversations", isDirectory: true)
    }

    private static nonisolated var indexURL: URL {
        historyDirectory.appendingPathComponent("index.json")
    }

    private static let worktreeTaskTitlesKey = "worktreeTaskTitlesByBranch"
    private static let worktreeConversationIdsKey = "worktreeConversationIdsByBranch"
    private static let recentWorkspacePathsKey = "recentWorkspacePaths"

    var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationId }
    }

    var hasRunningConversations: Bool {
        !runningConversationIds.isEmpty
    }

    func isConversationRunning(_ conversationId: UUID) -> Bool {
        runningConversationIds.contains(conversationId)
    }

    /// Number of conversations that finished but haven't been viewed yet.
    var unreadReadyCount: Int {
        unreadReadyConversationIds.count
    }

    /// Running conversations, ordered by most recent activity.
    var inboxRunningSummaries: [ConversationSummary] {
        summaries
            .filter { runningConversationIds.contains($0.id) }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Finished (unread) conversations, ordered by most recent activity.
    var inboxUnreadSummaries: [ConversationSummary] {
        summaries
            .filter { unreadReadyConversationIds.contains($0.id) }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    var activeConversationHasPendingUserInput: Bool {
        activeConversation?.hasPendingUserInput ?? false
    }

    /// Mark a conversation as read, removing it from the unread badge count.
    func markConversationRead(_ id: UUID) {
        unreadReadyConversationIds.remove(id)
    }

    func worktreeTaskTitle(for branch: String) -> String? {
        let normalizedBranch = normalizedWorktreeBranch(branch)
        guard !normalizedBranch.isEmpty else { return nil }
        return worktreeTaskTitlesByBranch[normalizedBranch]
    }

    func conversationId(forWorktreeBranch branch: String) -> UUID? {
        let normalizedBranch = normalizedWorktreeBranch(branch)
        guard !normalizedBranch.isEmpty,
              let raw = worktreeConversationIdsByBranch[normalizedBranch] else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    func worktreeBranch(for conversationId: UUID) -> String? {
        let rawId = conversationId.uuidString
        return worktreeConversationIdsByBranch.first(where: { $0.value == rawId })?.key
    }

    func bindWorktreeBranch(_ branch: String, to conversationId: UUID, title: String? = nil) {
        rememberWorktreeConversation(branch: branch, conversationId: conversationId)
        rememberWorktreeTaskTitle(branch: branch, conversationId: conversationId, titleOverride: title)
    }

    private func normalizedWorktreeBranch(_ branch: String) -> String {
        branch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeWorktreeTitle(_ title: String) -> String? {
        let cleanedTitle = title
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleanedTitle.isEmpty,
              cleanedTitle != "New Chat" else {
            return nil
        }

        return cleanedTitle.count > 72 ? String(cleanedTitle.prefix(69)) + "…" : cleanedTitle
    }

    private func rememberWorktreeConversation(branch: String, conversationId: UUID) {
        let normalizedBranch = normalizedWorktreeBranch(branch)
        guard !normalizedBranch.isEmpty else { return }

        let conversationRawId = conversationId.uuidString
        if worktreeConversationIdsByBranch[normalizedBranch] != conversationRawId {
            worktreeConversationIdsByBranch[normalizedBranch] = conversationRawId
            UserDefaults.standard.set(worktreeConversationIdsByBranch, forKey: Self.worktreeConversationIdsKey)
        }
    }

    private func rememberWorktreeTaskTitle(branch: String, conversationId: UUID, titleOverride: String? = nil) {
        let normalizedBranch = normalizedWorktreeBranch(branch)
        guard !normalizedBranch.isEmpty else { return }

        rememberWorktreeConversation(branch: normalizedBranch, conversationId: conversationId)

        let rawTitle = titleOverride
            ?? summaries.first(where: { $0.id == conversationId })?.title
            ?? conversations.first(where: { $0.id == conversationId })?.messages.first(where: { $0.role == .user })?.content

        guard let rawTitle,
              let finalTitle = normalizeWorktreeTitle(rawTitle) else {
            return
        }

        if worktreeTaskTitlesByBranch[normalizedBranch] != finalTitle {
            worktreeTaskTitlesByBranch[normalizedBranch] = finalTitle
            UserDefaults.standard.set(worktreeTaskTitlesByBranch, forKey: Self.worktreeTaskTitlesKey)
        }
    }

    private func rehydrateWorktreeTaskTitlesFromHistoryIfNeeded() {
        guard worktreeTaskTitlesByBranch.isEmpty else { return }

        let candidates = summaries
            .prefix(160)
            .map { ($0.id, $0.title) }

        guard !candidates.isEmpty else { return }

        Task { [weak self] in
            let recovered = await Self.recoverWorktreeTaskTitles(candidates: candidates)
            guard let self, !recovered.isEmpty else { return }

            var changed = false
            for (branch, title) in recovered {
                guard self.worktreeTaskTitlesByBranch[branch] == nil else { continue }
                self.worktreeTaskTitlesByBranch[branch] = title
                changed = true
            }

            if changed {
                UserDefaults.standard.set(self.worktreeTaskTitlesByBranch, forKey: Self.worktreeTaskTitlesKey)
            }
        }
    }

    private func rehydrateWorktreeConversationMappingsFromHistoryIfNeeded() {
        guard worktreeConversationIdsByBranch.isEmpty else { return }

        let candidates = summaries
            .prefix(160)
            .map(\.id)

        guard !candidates.isEmpty else { return }

        Task { [weak self] in
            let recovered = await Self.recoverWorktreeConversationMappings(candidates: candidates)
            guard let self, !recovered.isEmpty else { return }

            var changed = false
            for (branch, conversationId) in recovered {
                guard self.worktreeConversationIdsByBranch[branch] == nil else { continue }
                self.worktreeConversationIdsByBranch[branch] = conversationId
                changed = true
            }

            if changed {
                UserDefaults.standard.set(self.worktreeConversationIdsByBranch, forKey: Self.worktreeConversationIdsKey)
            }
        }
    }

    private static func recoverWorktreeTaskTitles(candidates: [(UUID, String)]) async -> [String: String] {
        await Task.detached(priority: .utility) {
            var recovered: [String: String] = [:]
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for (id, rawTitle) in candidates {
                let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty, trimmedTitle != "New Chat" else { continue }

                let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
                guard let data = try? Data(contentsOf: url),
                      let conversation = try? decoder.decode(Conversation.self, from: data) else {
                    continue
                }

                for message in conversation.messages {
                    for toolCall in message.toolCalls where toolCall.toolName == "set_worktree" {
                        let branch = toolCall.inputSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !branch.isEmpty, recovered[branch] == nil else { continue }
                        recovered[branch] = trimmedTitle
                    }
                }
            }

            return recovered
        }.value
    }

    private static func recoverWorktreeConversationMappings(candidates: [UUID]) async -> [String: String] {
        await Task.detached(priority: .utility) {
            var recovered: [String: String] = [:]
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for id in candidates {
                let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
                guard let data = try? Data(contentsOf: url),
                      let conversation = try? decoder.decode(Conversation.self, from: data) else {
                    continue
                }

                for message in conversation.messages {
                    for toolCall in message.toolCalls where toolCall.toolName == "set_worktree" {
                        let branch = toolCall.inputSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !branch.isEmpty, recovered[branch] == nil else { continue }
                        recovered[branch] = id.uuidString
                    }
                }
            }

            return recovered
        }.value
    }

    // MARK: - Lifecycle

    init() {
        recentWorkspacePaths = UserDefaults.standard.stringArray(forKey: Self.recentWorkspacePathsKey) ?? []
        workspacePath = UserDefaults.standard.string(forKey: "workspacePath")
        loadIndex()
        worktreeTaskTitlesByBranch = UserDefaults.standard.dictionary(forKey: Self.worktreeTaskTitlesKey) as? [String: String] ?? [:]
        worktreeConversationIdsByBranch = UserDefaults.standard.dictionary(forKey: Self.worktreeConversationIdsKey) as? [String: String] ?? [:]
        rehydrateWorktreeTaskTitlesFromHistoryIfNeeded()
        rehydrateWorktreeConversationMappingsFromHistoryIfNeeded()
    }

    private func recordRecentWorkspacePath(_ path: String?) {
        guard let path else { return }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path

        var updated = recentWorkspacePaths.filter { $0 != normalized }
        updated.insert(normalized, at: 0)

        if updated.count > 5 {
            updated = Array(updated.prefix(5))
        }

        guard updated != recentWorkspacePaths else { return }

        recentWorkspacePaths = updated
        UserDefaults.standard.set(updated, forKey: Self.recentWorkspacePathsKey)
    }

    // MARK: - Conversation CRUD

    func createConversation(modelSpec: String? = nil, thinkingLevel: ThinkingLevel? = nil) -> Conversation {
        var conversation = Conversation()
        conversation.modelSpec = modelSpec
        conversation.thinkingLevel = thinkingLevel
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

        // Load from disk synchronously (fast path), but actual file I/O is async.
        if let loaded = loadConversationSync(id: id) {
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
        // Flush any pending stream buffer before adding a new message.
        flushStreamBuffer()
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let message = Message(role: role, content: content, imageAttachments: imageAttachments)
        conversations[index].messages.append(message)
        conversations[index].invalidateDisplaySegments()

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
        conversations[index].invalidateDisplaySegments()
        debouncedSave(conversations[index])
    }

    // MARK: - Streaming Chunk Buffer

    /// Buffer that accumulates stream chunks between throttled flushes.
    /// This prevents per-chunk @Observable mutations that would cause
    /// SwiftUI to re-render/re-parse MarkdownUI on every single chunk,
    /// which overwhelms the main thread on long conversations.
    private var streamBuffer: String = ""
    private var streamBufferConversationId: UUID?
    private var streamFlushTimer: Timer?
    /// Interval between UI-visible flushes during streaming (seconds).
    private static let streamFlushInterval: TimeInterval = 0.05

    func appendToLastAssistantMessage(in conversationId: UUID, chunk: String) {
        streamBuffer.append(chunk)
        streamBufferConversationId = conversationId

        // If no flush is pending, schedule one.
        guard streamFlushTimer == nil else { return }
        streamFlushTimer = Timer.scheduledTimer(withTimeInterval: Self.streamFlushInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushStreamBuffer()
            }
        }
    }

    /// Flush any buffered stream content to the @Observable state.
    /// Called by the throttle timer and when streaming ends.
    func flushStreamBuffer() {
        streamFlushTimer?.invalidate()
        streamFlushTimer = nil

        guard !streamBuffer.isEmpty,
              let conversationId = streamBufferConversationId,
              let index = conversations.firstIndex(where: { $0.id == conversationId }),
              let lastIndex = conversations[index].messages.lastIndex(where: { $0.role == .assistant }) else {
            streamBuffer = ""
            return
        }

        conversations[index].messages[lastIndex].content.append(streamBuffer)
        conversations[index].invalidateDisplaySegments()
        streamBuffer = ""
        debouncedSave(conversations[index])
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    // MARK: - Tool Call Tracking

    func addToolCall(to conversationId: UUID, info: ToolCallInfo) {
        // Flush any pending stream buffer — a tool call means text streaming
        // for the current assistant message has ended.
        flushStreamBuffer()
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].toolCalls.append(info)
            conversations[index].invalidateDisplaySegments()
        } else {
            var message = Message(role: .assistant, content: "")
            message.toolCalls.append(info)
            conversations[index].messages.append(message)
            conversations[index].invalidateDisplaySegments()
        }

        if info.toolName == "set_worktree" {
            rememberWorktreeTaskTitle(branch: info.inputSummary, conversationId: conversationId)
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

                let toolCall = conversations[convIndex].messages[msgIndex].toolCalls[tcIndex]
                if toolCall.toolName == "set_worktree" {
                    rememberWorktreeTaskTitle(branch: toolCall.inputSummary, conversationId: conversationId)
                }

                conversations[convIndex].invalidateDisplaySegments()
                saveConversation(conversations[convIndex])
                lastScrollConversationId = conversationId
                scrollRevision &+= 1
                return
            }
        }
    }

    // MARK: - Permission Request Tracking

    func addPermissionRequest(to conversationId: UUID, request: PendingPermissionRequest) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].permissionRequests.append(request)
            conversations[index].invalidateDisplaySegments()
        } else {
            var message = Message(role: .assistant, content: "")
            message.permissionRequests.append(request)
            conversations[index].messages.append(message)
            conversations[index].invalidateDisplaySegments()
        }
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    func resolvePermissionRequest(in conversationId: UUID, requestId: String, approved: Bool) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let reqIndex = conversations[convIndex].messages[msgIndex].permissionRequests.firstIndex(where: { $0.id == requestId }) {
                conversations[convIndex].messages[msgIndex].permissionRequests[reqIndex].status = approved ? .approved : .denied
                conversations[convIndex].invalidateDisplaySegments()
                saveConversation(conversations[convIndex])
                return
            }
        }
    }

    // MARK: - Ask User Question Tracking

    func addAskUserQuestion(to conversationId: UUID, question: PendingAskUserQuestion) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].askUserQuestions.append(question)
            conversations[index].invalidateDisplaySegments()
        } else {
            var message = Message(role: .assistant, content: "")
            message.askUserQuestions.append(question)
            conversations[index].messages.append(message)
            conversations[index].invalidateDisplaySegments()
        }
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    func resolveAskUserQuestion(in conversationId: UUID, requestId: String, answers: [String: String]) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let reqIndex = conversations[convIndex].messages[msgIndex].askUserQuestions.firstIndex(where: { $0.id == requestId }) {
                conversations[convIndex].messages[msgIndex].askUserQuestions[reqIndex].status = .answered
                conversations[convIndex].messages[msgIndex].askUserQuestions[reqIndex].answers = answers
                conversations[convIndex].invalidateDisplaySegments()
                saveConversation(conversations[convIndex])
                return
            }
        }
    }

    // MARK: - Sub-Agent Tracking

    func addSubAgentActivity(to conversationId: UUID, activity: SubAgentActivity) {
        flushStreamBuffer()
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        if let lastIndex = conversations[index].messages.indices.last,
           conversations[index].messages[lastIndex].role == .assistant {
            conversations[index].messages[lastIndex].subAgentActivities.append(activity)
            conversations[index].invalidateDisplaySegments()
        } else {
            var message = Message(role: .assistant, content: "")
            message.subAgentActivities.append(activity)
            conversations[index].messages.append(message)
            conversations[index].invalidateDisplaySegments()
        }
        lastScrollConversationId = conversationId
        scrollRevision &+= 1
    }

    func addSubAgentToolCall(in conversationId: UUID, parentToolUseId: String, info: ToolCallInfo) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let actIndex = conversations[convIndex].messages[msgIndex].subAgentActivities.firstIndex(where: { $0.id == parentToolUseId }) {
                conversations[convIndex].messages[msgIndex].subAgentActivities[actIndex].toolCalls.append(info)
                conversations[convIndex].invalidateDisplaySegments()
                return
            }
        }
    }

    func completeSubAgentToolCall(in conversationId: UUID, parentToolUseId: String, subToolName: String) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let actIndex = conversations[convIndex].messages[msgIndex].subAgentActivities.firstIndex(where: { $0.id == parentToolUseId }) {
                if let tcIndex = conversations[convIndex].messages[msgIndex].subAgentActivities[actIndex].toolCalls.lastIndex(where: { $0.toolName == subToolName && $0.status == .pending }) {
                    conversations[convIndex].messages[msgIndex].subAgentActivities[actIndex].toolCalls[tcIndex].status = .complete
                    conversations[convIndex].invalidateDisplaySegments()
                }
                return
            }
        }
    }

    func completeSubAgent(in conversationId: UUID, toolUseId: String, resultPreview: String?) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        for msgIndex in conversations[convIndex].messages.indices.reversed() {
            if let actIndex = conversations[convIndex].messages[msgIndex].subAgentActivities.firstIndex(where: { $0.id == toolUseId }) {
                conversations[convIndex].messages[msgIndex].subAgentActivities[actIndex].status = .complete
                conversations[convIndex].messages[msgIndex].subAgentActivities[actIndex].resultPreview = resultPreview
                conversations[convIndex].invalidateDisplaySegments()
                saveConversation(conversations[convIndex])
                lastScrollConversationId = conversationId
                scrollRevision &+= 1
                return
            }
        }
    }

    // MARK: - History Management

    /// Load a conversation from disk into memory and set it as active.
    ///
    /// Important: this avoids synchronous file I/O on the main actor to prevent
    /// UI stalls when opening large conversation logs from history/at-a-glance.
    func openConversation(id: UUID) {
        markConversationRead(id)

        if let existing = conversations.first(where: { $0.id == id }) {
            activeConversationId = existing.id
            return
        }

        guard !loadingConversationIds.contains(id) else { return }
        loadingConversationIds.insert(id)

        Task { [weak self] in
            guard let self else { return }
            let loaded = await self.loadConversation(id: id)
            guard !Task.isCancelled else { return }

            self.loadingConversationIds.remove(id)

            // Conversation may have been created/loaded while async I/O was in flight.
            if let existing = self.conversations.first(where: { $0.id == id }) {
                self.activeConversationId = existing.id
                return
            }

            if let loaded {
                self.conversations.append(loaded)
                self.activeConversationId = loaded.id
            }
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
        unreadReadyConversationIds.remove(id)

        let rawId = id.uuidString
        let removedBranches = worktreeConversationIdsByBranch
            .filter { $0.value == rawId }
            .map(\.key)

        for branch in removedBranches {
            worktreeConversationIdsByBranch.removeValue(forKey: branch)
            worktreeTaskTitlesByBranch.removeValue(forKey: branch)
        }

        if !removedBranches.isEmpty {
            UserDefaults.standard.set(worktreeConversationIdsByBranch, forKey: Self.worktreeConversationIdsKey)
            UserDefaults.standard.set(worktreeTaskTitlesByBranch, forKey: Self.worktreeTaskTitlesKey)
        }

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
            if let branch = worktreeBranch(for: id),
               let normalizedTitle = normalizeWorktreeTitle(newTitle) {
                worktreeTaskTitlesByBranch[branch] = normalizedTitle
                UserDefaults.standard.set(worktreeTaskTitlesByBranch, forKey: Self.worktreeTaskTitlesKey)
            }
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
        } else if let loaded = loadConversationSync(id: id) {
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
        if !isRunning {
            // Flush any remaining stream buffer when streaming ends.
            flushStreamBuffer()
        }
        let wasRunning = runningConversationIds.contains(conversationId)
        if isRunning {
            runningConversationIds.insert(conversationId)
        } else {
            runningConversationIds.remove(conversationId)
            // If the conversation just finished, mark it as unread
            // (unless it's the currently viewed conversation while the island is open).
            if wasRunning && conversationId != activeConversationId {
                unreadReadyConversationIds.insert(conversationId)
            } else if wasRunning && conversationId == activeConversationId
                        && !IslandWindowManager.shared.isExpanded {
                unreadReadyConversationIds.insert(conversationId)
            }
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

    private static nonisolated func ensureDirectories() {
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
        // Perform file I/O off the main actor to avoid blocking UI.
        Task.detached(priority: .background) { [conversation] in
            Self.ensureDirectories()
            let url = Self.conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(conversation) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private var saveTimer: Timer?

    /// Debounce saves during streaming to avoid excessive disk writes.
    private func debouncedSave(_ conversation: Conversation) {
        saveTimer?.invalidate()
        let convCopy = conversation
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveConversation(convCopy)
                self?.saveIndex()
            }
        }
    }

    /// Synchronous version for backwards compatibility.
    /// Performs file I/O synchronously to ensure immediate persistence.
    private func loadConversationSync(id: UUID) -> Conversation? {
        let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Conversation.self, from: data)
    }

    /// Asynchronous version for when you want non-blocking I/O.
    private func loadConversation(id: UUID) async -> Conversation? {
        await Task.detached(priority: .userInitiated) {
            let url = Self.conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Conversation.self, from: data)
        }.value
    }

    // MARK: - Test Helpers

    /// Forces an immediate synchronous save of a conversation for testing.
    /// This ensures data is persisted before test assertions.
    func saveConversationSync(_ conversation: Conversation) {
        Self.ensureDirectories()
        let url = Self.conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Forces an immediate synchronous save of the index for testing.
    func saveIndexSync() {
        Self.ensureDirectories()
        let index = HistoryIndex(summaries: summaries, folders: folders)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(index) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    private struct HistoryIndex: Codable {
        var summaries: [ConversationSummary]
        var folders: [ChatFolder]
    }

    private func saveIndex() {
        // Capture local copies to avoid capturing self in detached task.
        let summariesCopy = summaries
        let foldersCopy = folders
        Task.detached(priority: .background) {
            Self.ensureDirectories()
            let index = HistoryIndex(summaries: summariesCopy, folders: foldersCopy)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(index) {
                try? data.write(to: Self.indexURL, options: .atomic)
            }
        }
    }

    private func loadIndex() {
        // Load index synchronously during initialization - needed for immediate data access
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let index = try? decoder.decode(HistoryIndex.self, from: data) else { return }
        summaries = index.summaries
        folders = index.folders
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [Message]
    let createdAt: Date
    var modelSpec: String?
    var thinkingLevel: ThinkingLevel?

    /// Class-based box so the cache survives struct copies without triggering
    /// copy-on-write of the whole Conversation value.
    /// Marked as unchecked Sendable since it's only accessed from @MainActor.
    private final class SegmentCache: @unchecked Sendable {
        var segments: [DisplaySegment]?
    }
    private var _segmentCache = SegmentCache()

    init(
        id: UUID = UUID(),
        messages: [Message] = [],
        createdAt: Date = Date(),
        modelSpec: String? = nil,
        thinkingLevel: ThinkingLevel? = nil
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.modelSpec = modelSpec
        self.thinkingLevel = thinkingLevel
    }

    // Exclude the cache from Codable.
    private enum CodingKeys: String, CodingKey {
        case id, messages, createdAt, modelSpec, thinkingLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        messages = try container.decode([Message].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modelSpec = try container.decodeIfPresent(String.self, forKey: .modelSpec)
        thinkingLevel = try container.decodeIfPresent(ThinkingLevel.self, forKey: .thinkingLevel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(messages, forKey: .messages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(modelSpec, forKey: .modelSpec)
        try container.encodeIfPresent(thinkingLevel, forKey: .thinkingLevel)
    }

    var hasPendingUserInput: Bool {
        messages.contains { message in
            message.permissionRequests.contains { $0.status == .pending }
            || message.askUserQuestions.contains { $0.status == .pending }
        }
    }

    /// Clear the cached display segments so the next access rebuilds them.
    mutating func invalidateDisplaySegments() {
        _segmentCache.segments = nil
    }

    /// Number of display segments in this conversation.
    /// Used to support progressive rendering in the chat UI without building
    /// the full `[DisplaySegment]` array up front.
    var displaySegmentCount: Int {
        messages.reduce(into: 0) { count, message in
            switch message.role {
            case .user, .system:
                count += 1
            case .assistant:
                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    count += 1
                }
                if !message.toolCalls.isEmpty {
                    count += 1
                }
                count += message.permissionRequests.count
                count += message.askUserQuestions.count
                count += message.subAgentActivities.count
            }
        }
    }

    /// Tail-only version that avoids constructing all display segments when we
    /// only need the latest portion of a long conversation.
    func displaySegmentsTail(limit: Int) -> [DisplaySegment] {
        guard limit > 0 else { return [] }

        var reversedTail: [DisplaySegment] = []
        reversedTail.reserveCapacity(limit)

        for message in messages.reversed() {
            let messageSegments = Self.segments(for: message)
            for segment in messageSegments.reversed() {
                reversedTail.append(segment)
                if reversedTail.count == limit {
                    return Array(reversedTail.reversed())
                }
            }
        }

        return Array(reversedTail.reversed())
    }

    /// Produces display segments for the chat view by grouping tool calls and
    /// separating them from assistant text content. Results are cached until
    /// explicitly invalidated.
    var displaySegments: [DisplaySegment] {
        if let cached = _segmentCache.segments {
            return cached
        }

        let segments = messages.flatMap(Self.segments(for:))
        _segmentCache.segments = segments
        return segments
    }

    private static func segments(for message: Message) -> [DisplaySegment] {
        switch message.role {
        case .user:
            return [.userMessage(message)]

        case .assistant:
            var segments: [DisplaySegment] = []
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.assistantText(message))
            }
            if !message.toolCalls.isEmpty {
                segments.append(.toolCallGroup(id: message.id.uuidString, calls: message.toolCalls))
            }
            segments.append(contentsOf: message.permissionRequests.map(DisplaySegment.permissionRequest))
            segments.append(contentsOf: message.askUserQuestions.map(DisplaySegment.askUserQuestion))
            segments.append(contentsOf: message.subAgentActivities.map(DisplaySegment.subAgentGroup))
            return segments

        case .system:
            return [.assistantText(message)]
        }
    }
}

// MARK: - Message

struct Message: Identifiable, Codable {
    let id: UUID
    var role: Role
    var content: String
    var imageAttachments: [MessageImageAttachment]
    var toolCalls: [ToolCallInfo]
    var permissionRequests: [PendingPermissionRequest]
    var askUserQuestions: [PendingAskUserQuestion]
    var subAgentActivities: [SubAgentActivity]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        imageAttachments: [MessageImageAttachment] = [],
        toolCalls: [ToolCallInfo] = [],
        permissionRequests: [PendingPermissionRequest] = [],
        askUserQuestions: [PendingAskUserQuestion] = [],
        subAgentActivities: [SubAgentActivity] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageAttachments = imageAttachments
        self.toolCalls = toolCalls
        self.permissionRequests = permissionRequests
        self.askUserQuestions = askUserQuestions
        self.subAgentActivities = subAgentActivities
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case imageAttachments
        case toolCalls
        case permissionRequests
        case askUserQuestions
        case subAgentActivities
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        imageAttachments = try container.decodeIfPresent([MessageImageAttachment].self, forKey: .imageAttachments) ?? []
        toolCalls = try container.decodeIfPresent([ToolCallInfo].self, forKey: .toolCalls) ?? []
        permissionRequests = try container.decodeIfPresent([PendingPermissionRequest].self, forKey: .permissionRequests) ?? []
        askUserQuestions = try container.decodeIfPresent([PendingAskUserQuestion].self, forKey: .askUserQuestions) ?? []
        subAgentActivities = try container.decodeIfPresent([SubAgentActivity].self, forKey: .subAgentActivities) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(imageAttachments, forKey: .imageAttachments)
        try container.encode(toolCalls, forKey: .toolCalls)
        try container.encode(permissionRequests, forKey: .permissionRequests)
        try container.encode(askUserQuestions, forKey: .askUserQuestions)
        try container.encode(subAgentActivities, forKey: .subAgentActivities)
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
