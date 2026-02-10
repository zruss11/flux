import Foundation

@Observable
final class AgentBridge: @unchecked Sendable {
    var isConnected = false

    var onAssistantMessage: ((String, String) -> Void)?  // conversationId, content
    var onToolRequest: ((String, String, String, [String: Any]) -> Void)?  // conversationId, toolUseId, toolName, input
    var onStreamChunk: ((String, String) -> Void)?  // conversationId, content

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private var shouldReconnect = true
    private var reconnectWorkItem: DispatchWorkItem?

    private let port: Int
    private var lastSentLinearMcpToken: String = ""

    init(port: Int = 7847) {
        self.port = port
    }

    func connect() {
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

        receiveMessage()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        Task { @MainActor in
            isConnected = false
        }
    }

    func sendChatMessage(conversationId: String, content: String) {
        // Keep sidecar config in sync (user may have edited settings since connect).
        sendMcpAuthIfNeeded()

        let message: [String: Any] = [
            "type": "chat",
            "conversationId": conversationId,
            "content": content
        ]
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

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(string)) { [weak self] error in
            if let error {
                print("WebSocket send error: \(error)")
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
                print("WebSocket receive error: \(error)")
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
            }

        default:
            print("Unknown message type: \(type)")
        }
    }

    private func handleDisconnect() {
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
            print("Reconnecting in \(delay)s...")
            self.connect()
        }
        reconnectWorkItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
    }
}
