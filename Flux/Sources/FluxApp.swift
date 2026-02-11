import SwiftUI
import Foundation

@main
struct FluxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let conversationStore = ConversationStore()
    private let agentBridge = AgentBridge()
    private let contextManager = ContextManager()
    private let accessibilityReader = AccessibilityReader()
    private let screenCapture = ScreenCapture()
    private let toolRunner = ToolRunner()
    private let automationService = AutomationService.shared

    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        SecretMigration.migrateUserDefaultsTokensToKeychainIfNeeded()

        setupStatusItem()
        setupAutomationThreadObserver()

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if hasCompletedOnboarding {
            launchMainApp()
        } else {
            showOnboarding()
        }
    }

    func showOnboarding() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.launchMainApp()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Flux"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    private func launchMainApp() {
        setupBridgeCallbacks()
        automationService.configureRunner { [weak self] request in
            guard let self else { return false }
            guard self.agentBridge.isConnected else { return false }
            guard let conversationId = UUID(uuidString: request.conversationId) else { return false }

            let automationName = self.automationService.automations
                .first(where: { $0.id == request.automationId })?
                .name ?? "Automation"
            self.conversationStore.ensureConversationExists(
                id: conversationId,
                title: "Automation: \(automationName)"
            )

            self.agentBridge.sendChatMessage(
                conversationId: conversationId.uuidString,
                content: request.content
            )
            return true
        }
        agentBridge.connect()

        IslandWindowManager.shared.showIsland(
            conversationStore: conversationStore,
            agentBridge: agentBridge
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "Flux"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show/Hide Island", action: #selector(toggleIslandFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flux", action: #selector(quitFromMenu), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func setupAutomationThreadObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAutomationOpenThreadNotification(_:)),
            name: .automationOpenThreadRequested,
            object: nil
        )
    }

    @objc
    private func handleAutomationOpenThreadNotification(_ notification: Notification) {
        handleAutomationOpenThread(notification)
    }

    private func handleAutomationOpenThread(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let conversationIdRaw = userInfo[NotificationPayloadKey.conversationId] as? String,
              let conversationId = UUID(uuidString: conversationIdRaw) else {
            return
        }

        let title = (userInfo[NotificationPayloadKey.conversationTitle] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = title.isEmpty ? "Automation" : title

        let islandWasShown = IslandWindowManager.shared.isShown
        if !islandWasShown {
            IslandWindowManager.shared.showIsland(
                conversationStore: conversationStore,
                agentBridge: agentBridge
            )
        }

        conversationStore.ensureConversationExists(
            id: conversationId,
            title: resolvedTitle
        )
        conversationStore.openConversation(id: conversationId)
        IslandWindowManager.shared.expand()

        if islandWasShown {
            NotificationCenter.default.post(
                name: .islandOpenConversationRequested,
                object: nil,
                userInfo: [NotificationPayloadKey.conversationId: conversationId.uuidString]
            )
        }
    }

    @objc private func toggleIslandFromMenu() {
        if IslandWindowManager.shared.isShown {
            IslandWindowManager.shared.hideIsland()
        } else {
            IslandWindowManager.shared.showIsland(conversationStore: conversationStore, agentBridge: agentBridge)
        }
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func setupBridgeCallbacks() {
        agentBridge.onAssistantMessage = { [weak self] conversationId, content in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                self.conversationStore.addMessage(to: uuid, role: .assistant, content: content)
                self.conversationStore.setConversationRunning(uuid, isRunning: false)
            }
        }

        agentBridge.onStreamChunk = { [weak self] conversationId, content in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }

            Task { @MainActor in
                self.conversationStore.setConversationRunning(uuid, isRunning: true)
                if let conversation = self.conversationStore.conversations.first(where: { $0.id == uuid }),
                   let lastMessage = conversation.messages.last,
                   lastMessage.role == .assistant,
                   lastMessage.toolCalls.isEmpty {
                    self.conversationStore.appendToLastAssistantMessage(in: uuid, chunk: content)
                } else {
                    self.conversationStore.addMessage(to: uuid, role: .assistant, content: content)
                }
            }
        }

        agentBridge.onToolRequest = { [weak self] conversationId, toolUseId, toolName, input in
            guard let self else { return }
            Task {
                let result = await self.handleToolRequest(
                    toolName: toolName,
                    input: input
                )
                self.agentBridge.sendToolResult(
                    conversationId: conversationId,
                    toolUseId: toolUseId,
                    toolName: toolName,
                    result: result
                )
            }
        }

        agentBridge.onToolUseStart = { [weak self] conversationId, toolUseId, toolName, inputSummary in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            let info = ToolCallInfo(id: toolUseId, toolName: toolName, inputSummary: inputSummary)
            Task { @MainActor in
                self.conversationStore.setConversationRunning(uuid, isRunning: true)
                self.conversationStore.addToolCall(to: uuid, info: info)
            }
        }

        agentBridge.onToolUseComplete = { [weak self] conversationId, toolUseId, _, resultPreview in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                self.conversationStore.completeToolCall(in: uuid, toolUseId: toolUseId, resultPreview: resultPreview)
            }
        }

        agentBridge.onRunStatus = { [weak self] conversationId, isWorking in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                self.conversationStore.setConversationRunning(uuid, isRunning: isWorking)
            }
        }
    }

    private func handleToolRequest(toolName: String, input: [String: Any]) async -> String {
        let intInput: (String) -> Int? = { key in
            if let value = input[key] as? Int {
                return value
            }
            if let value = input[key] as? Double {
                return Int(value)
            }
            if let value = input[key] as? NSNumber {
                return value.intValue
            }
            return nil
        }

        switch toolName {
        case "capture_screen":
            let target = input["target"] as? String ?? "display"
            if target == "window" {
                return await screenCapture.captureFrontmostWindow() ?? "Failed to capture window"
            } else {
                return await screenCapture.captureMainDisplay() ?? "Failed to capture display"
            }

        case "read_ax_tree":
            if let tree = await accessibilityReader.readFrontmostWindow() {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(tree), let json = String(data: data, encoding: .utf8) {
                    return json
                }
            }
            return "Failed to read accessibility tree"

        case "read_visible_windows":
            let maxApps = intInput("maxApps")
            let maxWindowsPerApp = intInput("maxWindowsPerApp")
            let maxElementsPerWindow = intInput("maxElementsPerWindow")
            let maxTextLength = intInput("maxTextLength")
            let includeMinimized = input["includeMinimized"] as? Bool
            return await accessibilityReader.readVisibleWindowsContext(
                maxApps: maxApps,
                maxWindowsPerApp: maxWindowsPerApp,
                maxElementsPerWindow: maxElementsPerWindow,
                maxTextLength: maxTextLength,
                includeMinimized: includeMinimized
            ) ?? "Failed to read visible windows accessibility context"

        case "read_selected_text":
            return await accessibilityReader.readSelectedText() ?? "No text selected"

        case "execute_applescript":
            let script = input["script"] as? String ?? ""
            return await toolRunner.executeAppleScript(script)

        case "run_shell_command":
            let command = input["command"] as? String ?? ""
            return await toolRunner.executeShellScript(command)

        case "send_slack_message":
            let text = input["text"] as? String ?? ""
            let channelOverride = (input["channelId"] as? String) ?? (input["channel"] as? String)
            return await sendSlackMessage(text: text, channelIdOverride: channelOverride)

        case "send_discord_message":
            let content = input["content"] as? String ?? ""
            let channelIdOverride = input["channelId"] as? String
            return await sendDiscordMessage(content: content, channelIdOverride: channelIdOverride)

        case "send_telegram_message":
            let text = input["text"] as? String ?? ""
            let chatIdOverride = input["chatId"] as? String
            return await sendTelegramMessage(text: text, chatIdOverride: chatIdOverride)

        case "create_automation":
            let name = input["name"] as? String
            let prompt = input["prompt"] as? String ?? ""
            let scheduleExpression = (input["scheduleExpression"] as? String)
                ?? (input["schedule"] as? String)
                ?? (input["cron"] as? String)
                ?? ""
            let timezone = input["timezone"] as? String
            do {
                let automation = try automationService.createAutomation(
                    name: name,
                    prompt: prompt,
                    scheduleExpression: scheduleExpression,
                    timezoneIdentifier: timezone
                )
                return encodeJSON(AutomationMutationResponse(
                    ok: true,
                    message: "Automation created.",
                    automation: automation
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        case "list_automations":
            return encodeJSON(AutomationListResponse(ok: true, automations: automationService.automations))

        case "update_automation":
            let id = input["id"] as? String ?? ""
            let name = input["name"] as? String
            let prompt = input["prompt"] as? String
            let scheduleExpression = (input["scheduleExpression"] as? String)
                ?? (input["schedule"] as? String)
                ?? (input["cron"] as? String)
            let timezone = input["timezone"] as? String

            do {
                let automation = try automationService.updateAutomation(
                    id: id,
                    name: name,
                    prompt: prompt,
                    scheduleExpression: scheduleExpression,
                    timezoneIdentifier: timezone
                )
                return encodeJSON(AutomationMutationResponse(
                    ok: true,
                    message: "Automation updated.",
                    automation: automation
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        case "pause_automation":
            let id = input["id"] as? String ?? ""
            do {
                let automation = try automationService.pauseAutomation(id: id)
                return encodeJSON(AutomationMutationResponse(
                    ok: true,
                    message: "Automation paused.",
                    automation: automation
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        case "resume_automation":
            let id = input["id"] as? String ?? ""
            do {
                let automation = try automationService.resumeAutomation(id: id)
                return encodeJSON(AutomationMutationResponse(
                    ok: true,
                    message: "Automation resumed.",
                    automation: automation
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        case "delete_automation":
            let id = input["id"] as? String ?? ""
            do {
                try automationService.deleteAutomation(id: id)
                return encodeJSON(AutomationDeleteResponse(
                    ok: true,
                    message: "Automation deleted.",
                    id: id
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        case "run_automation_now":
            let id = input["id"] as? String ?? ""
            do {
                let automation = try automationService.runAutomationNow(id: id)
                return encodeJSON(AutomationMutationResponse(
                    ok: true,
                    message: "Automation dispatched.",
                    automation: automation
                ))
            } catch {
                return encodeJSON(AutomationErrorResponse(ok: false, error: error.localizedDescription))
            }

        default:
            return "Unknown tool: \(toolName)"
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"Failed to encode JSON response.\"}"
        }
        return json
    }

    private struct AutomationListResponse: Codable {
        let ok: Bool
        let automations: [Automation]
    }

    private struct AutomationMutationResponse: Codable {
        let ok: Bool
        let message: String
        let automation: Automation
    }

    private struct AutomationDeleteResponse: Codable {
        let ok: Bool
        let message: String
        let id: String
    }

    private struct AutomationErrorResponse: Codable {
        let ok: Bool
        let error: String
    }

    private func sendSlackMessage(text: String, channelIdOverride: String?) async -> String {
        let token = (KeychainService.getString(forKey: SecretKeys.slackBotToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = (channelIdOverride ?? UserDefaults.standard.string(forKey: "slackChannelId") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            return "Slack bot token not set. Open Flux Settings and set Slack Bot Token + Slack Channel ID."
        }
        guard !channel.isEmpty else {
            return "Slack channel ID not set. Open Flux Settings and set Slack Channel ID."
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Slack message text is empty."
        }

        var req = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "channel": channel,
            "text": text
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok = json?["ok"] as? Bool
            let error = json?["error"] as? String
            let ts = json?["ts"] as? String

            if status != 200 || ok != true {
                let rawText = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let raw = rawText.count > 500 ? String(rawText.prefix(500)) + "…" : rawText
                let detail = error ?? "HTTP \(status)"
                return "Slack send failed: \(detail)\(raw.isEmpty ? "" : " - \(raw)")"
            }

            return "Slack message sent (ts=\(ts ?? "unknown"))."
        } catch {
            return "Slack send failed: \(error.localizedDescription)"
        }
    }

    private func sendDiscordMessage(content: String, channelIdOverride: String?) async -> String {
        let token = (KeychainService.getString(forKey: SecretKeys.discordBotToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let channelId = (channelIdOverride ?? UserDefaults.standard.string(forKey: "discordChannelId") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            return "Discord bot token not set. Open Flux Settings and set Discord Bot Token + Discord Channel ID."
        }
        guard !channelId.isEmpty else {
            return "Discord channel ID not set. Open Flux Settings and set Discord Channel ID."
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Discord message content is empty."
        }

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages") else {
            return "Discord send failed: invalid channel ID."
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "content": content
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1

            if status < 200 || status >= 300 {
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return "Discord send failed: HTTP \(status)\(text.isEmpty ? "" : " - \(text)")"
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let messageId = json?["id"] as? String
            return "Discord message sent (id=\(messageId ?? "unknown"))."
        } catch {
            return "Discord send failed: \(error.localizedDescription)"
        }
    }

    private func sendTelegramMessage(text: String, chatIdOverride: String?) async -> String {
        let token = (KeychainService.getString(forKey: SecretKeys.telegramBotToken) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chatId = (chatIdOverride ?? UserDefaults.standard.string(forKey: "telegramChatId") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            return "Telegram bot token not set. Open Flux Settings and set Telegram Bot Token + Telegram Chat ID."
        }
        guard !chatId.isEmpty else {
            return "Telegram chat ID not set. Open Flux Settings and set Telegram Chat ID."
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Telegram message text is empty."
        }

        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            return "Telegram send failed: invalid bot token."
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "chat_id": chatId,
            "text": text
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok = json?["ok"] as? Bool
            let result = json?["result"] as? [String: Any]
            let messageId = result?["message_id"] as? Int

            if status != 200 || ok != true {
                let rawText = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let raw = rawText.count > 500 ? String(rawText.prefix(500)) + "…" : rawText
                return "Telegram send failed: HTTP \(status)\(raw.isEmpty ? "" : " - \(raw)")"
            }

            return "Telegram message sent (id=\(messageId.map(String.init) ?? "unknown"))."
        } catch {
            return "Telegram send failed: \(error.localizedDescription)"
        }
    }
}
