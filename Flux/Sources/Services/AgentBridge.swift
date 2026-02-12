import Foundation
import os

struct ChatImagePayload: Codable, Hashable, Sendable {
    let fileName: String
    let mediaType: String
    let data: String
}

@Observable
final class AgentBridge: @unchecked Sendable {
    var isConnected = false
    var isAgentWorking = false

    var onAssistantMessage: ((String, String) -> Void)?  // conversationId, content
    var onToolRequest: ((String, String, String, [String: Any]) -> Void)?  // conversationId, toolUseId, toolName, input
    var onStreamChunk: ((String, String) -> Void)?  // conversationId, content
    var onToolUseStart: ((String, String, String, String) -> Void)?  // conversationId, toolUseId, toolName, inputSummary
    var onToolUseComplete: ((String, String, String, String) -> Void)?  // conversationId, toolUseId, toolName, resultPreview
    var onRunStatus: ((String, Bool) -> Void)?  // conversationId, isWorking
    private var activeRunConversationIds: Set<String> = []
    private var activeToolUseIds: Set<String> = []
    private var activeStreamConversationIds: Set<String> = []
    private var streamIdleWorkItems: [String: DispatchWorkItem] = [:]
    private let streamIdleTimeout: TimeInterval = 1.2

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var shouldReconnect = true
    private var reconnectWorkItem: DispatchWorkItem?

    private let port: Int
    private var lastSentLinearMcpToken: String = ""
    private var lastSentTelegramBotToken: String?
    private var lastSentTelegramChatId: String?
    private var telegramConfigObserver: NSObjectProtocol?
    private var lastActiveAppUpdate: ActiveAppUpdatePayload?

    private struct ActiveAppUpdatePayload: Sendable {
        let appName: String
        let bundleId: String
        let pid: Int32
        let appInstruction: String?
    }

    init(port: Int = 7847) {
        self.port = port
        telegramConfigObserver = NotificationCenter.default.addObserver(
            forName: .telegramConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sendTelegramConfigFromStores()
        }
    }

    deinit {
        if let observer = telegramConfigObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func connect() {
        Log.bridge.info("Connecting to sidecar on port \(self.port)")
        clearRunState()
        shouldReconnect = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        // Avoid leaking multiple concurrent socket tasks/receive loops across reconnects.
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        guard let url = URL(string: "ws://localhost:\(port)") else { return }

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Send API key immediately on connection (don't wait for first receive)
        let storedKey = UserDefaults.standard.string(forKey: "anthropicApiKey") ?? ""
        sendApiKey(storedKey)

        // Send MCP auth config proactively; doesn't depend on receiving a message first.
        sendMcpAuthIfNeeded()
        sendTelegramConfigFromStores()
        if let activeApp = lastActiveAppUpdate {
            sendActiveAppUpdate(
                appName: activeApp.appName,
                bundleId: activeApp.bundleId,
                pid: activeApp.pid,
                appInstruction: activeApp.appInstruction
            )
        }

        receiveMessage()
    }

    func disconnect() {
        Log.bridge.info("Disconnecting from sidecar")
        shouldReconnect = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        clearRunState()
        Task { @MainActor in
            isConnected = false
        }
    }

    func sendChatMessage(conversationId: String, content: String, images: [ChatImagePayload] = []) {
        setRunStatus(for: conversationId, isWorking: true)

        // Keep sidecar config in sync (user may have edited settings since connect).
        sendMcpAuthIfNeeded()
        sendTelegramConfigFromStores()

        var message: [String: Any] = [
            "type": "chat",
            "conversationId": conversationId,
            "content": content
        ]
        if !images.isEmpty {
            message["images"] = images.map { image in
                [
                    "fileName": image.fileName,
                    "mediaType": image.mediaType,
                    "data": image.data
                ]
            }
        }
        send(message)
    }

    func sendToolResult(conversationId: String, toolUseId: String, toolName: String, result: String) {
        let message: [String: Any] = [
            "type": "tool_result",
            "conversationId": conversationId,
            "toolUseId": toolUseId,
            "toolName": toolName,
            "toolResult": result
        ]
        send(message)
    }

    func sendApiKey(_ key: String) {
        guard !key.isEmpty else { return }
        let message: [String: Any] = [
            "type": "set_api_key",
            "apiKey": key
        ]
        send(message)
    }

    /// Notify the sidecar of a frontmost-app change so it can adapt the system prompt.
    func sendActiveAppUpdate(appName: String, bundleId: String, pid: Int32, appInstruction: String? = nil) {
        lastActiveAppUpdate = ActiveAppUpdatePayload(
            appName: appName,
            bundleId: bundleId,
            pid: pid,
            appInstruction: appInstruction
        )
        var message: [String: Any] = [
            "type": "active_app_update",
            "appName": appName,
            "bundleId": bundleId,
            "pid": pid
        ]
        if let instruction = appInstruction, !instruction.isEmpty {
            message["appInstruction"] = instruction
        }
        send(message)
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(string)) { [weak self] error in
            if let error {
                Log.bridge.error("WebSocket send error: \(error)")
                self?.handleDisconnect()
            }
        }
    }

    private func sendMcpAuthIfNeeded() {
        let token = UserDefaults.standard.string(forKey: "linearMcpToken") ?? ""
        guard token != lastSentLinearMcpToken else { return }

        lastSentLinearMcpToken = token

        let message: [String: Any] = [
            "type": "mcp_auth",
            "serverId": "linear",
            "token": token
        ]
        send(message)
    }

    private func sendTelegramConfigFromStores() {
        let token = (KeychainService.getString(forKey: SecretKeys.telegramBotToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chatId = (UserDefaults.standard.string(forKey: "telegramChatId") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sendTelegramConfig(botToken: token, defaultChatId: chatId)
    }

    private func sendTelegramConfig(botToken: String, defaultChatId: String) {
        guard botToken != lastSentTelegramBotToken || defaultChatId != lastSentTelegramChatId else { return }
        lastSentTelegramBotToken = botToken
        lastSentTelegramChatId = defaultChatId

        let message: [String: Any] = [
            "type": "set_telegram_config",
            "botToken": botToken,
            "defaultChatId": defaultChatId
        ]
        send(message)
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    if !self.isConnected {
                        self.isConnected = true
                    }
                    self.reconnectDelay = 1.0
                }
                switch message {
                case .string(let text):
                    self.handleReceivedMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleReceivedMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                Log.bridge.error("WebSocket receive error: \(error)")
                self.handleDisconnect()
            }
        }
    }

    private func handleReceivedMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let conversationId = json["conversationId"] as? String else { return }

        switch type {
        case "assistant_message":
            if let content = json["content"] as? String {
                Task { @MainActor in
                    self.onAssistantMessage?(conversationId, content)
                }
                // Error and non-stream replies arrive as full assistant messages.
                setRunStatus(for: conversationId, isWorking: false)
                clearStreamActivity(for: conversationId)
            }

        case "tool_request":
            if let toolUseId = json["toolUseId"] as? String,
               let toolName = json["toolName"] as? String,
               let input = json["input"] as? [String: Any] {
                Task { @MainActor in
                    self.onToolRequest?(conversationId, toolUseId, toolName, input)
                }
            }

        case "stream_chunk":
            if let content = json["content"] as? String {
                Task { @MainActor in
                    self.onStreamChunk?(conversationId, content)
                }
                // Some sidecar paths can stream without a preceding local sendChat call.
                setRunStatus(for: conversationId, isWorking: true)
                registerStreamChunk(for: conversationId)
            }

        case "tool_use_start":
            if let toolUseId = json["toolUseId"] as? String,
               let toolName = json["toolName"] as? String,
               let inputSummary = json["inputSummary"] as? String {
                Task { @MainActor in
                    self.onToolUseStart?(conversationId, toolUseId, toolName, inputSummary)
                }
                setToolUseStatus(for: conversationId, toolUseId: toolUseId, isActive: true)
            }

        case "tool_use_complete":
            if let toolUseId = json["toolUseId"] as? String,
               let toolName = json["toolName"] as? String,
               let resultPreview = json["resultPreview"] as? String {
                Task { @MainActor in
                    self.onToolUseComplete?(conversationId, toolUseId, toolName, resultPreview)
                }
                setToolUseStatus(for: conversationId, toolUseId: toolUseId, isActive: false)
            }

        case "run_status":
            if let isWorking = json["isWorking"] as? Bool {
                Task { @MainActor in
                    self.onRunStatus?(conversationId, isWorking)
                }
                setRunStatus(for: conversationId, isWorking: isWorking)
            }

        default:
            Log.bridge.warning("Unknown message type: \(type)")
        }
    }

    private func handleDisconnect() {
        clearRunState()
        Task { @MainActor in
            isConnected = false
        }

        guard shouldReconnect else { return }

        // Ensure we don't schedule multiple overlapping reconnect attempts.
        if reconnectWorkItem != nil { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.shouldReconnect else { return }
            self.reconnectWorkItem = nil
            Log.bridge.info("Reconnecting in \(delay)s...")
            self.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func setRunStatus(for conversationId: String, isWorking: Bool) {
        Task { @MainActor in
            if isWorking {
                self.activeRunConversationIds.insert(conversationId)
            } else {
                self.activeRunConversationIds.remove(conversationId)
            }
            self.refreshWorkingFlag()
        }
    }

    private func clearRunState() {
        Task { @MainActor in
            for conversationId in self.activeRunConversationIds {
                self.onRunStatus?(conversationId, false)
            }
            self.activeRunConversationIds.removeAll()
            self.activeToolUseIds.removeAll()
            self.activeStreamConversationIds.removeAll()
            self.streamIdleWorkItems.values.forEach { $0.cancel() }
            self.streamIdleWorkItems.removeAll()
            self.refreshWorkingFlag()
        }
    }

    private func setToolUseStatus(for conversationId: String, toolUseId: String, isActive: Bool) {
        let key = "\(conversationId):\(toolUseId)"
        Task { @MainActor in
            if isActive {
                self.activeToolUseIds.insert(key)
            } else {
                self.activeToolUseIds.remove(key)
            }
            self.refreshWorkingFlag()
        }
    }

    private func refreshWorkingFlag() {
        isAgentWorking = !activeRunConversationIds.isEmpty
            || !activeToolUseIds.isEmpty
            || !activeStreamConversationIds.isEmpty
    }

    private func registerStreamChunk(for conversationId: String) {
        Task { @MainActor in
            self.activeStreamConversationIds.insert(conversationId)
            self.streamIdleWorkItems[conversationId]?.cancel()

            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.activeStreamConversationIds.remove(conversationId)
                    self.streamIdleWorkItems.removeValue(forKey: conversationId)
                    self.refreshWorkingFlag()
                }
            }
            self.streamIdleWorkItems[conversationId] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + self.streamIdleTimeout, execute: item)
            self.refreshWorkingFlag()
        }
    }

    private func clearStreamActivity(for conversationId: String) {
        Task { @MainActor in
            self.streamIdleWorkItems[conversationId]?.cancel()
            self.streamIdleWorkItems.removeValue(forKey: conversationId)
            self.activeStreamConversationIds.remove(conversationId)
            self.refreshWorkingFlag()
        }
    }
}
