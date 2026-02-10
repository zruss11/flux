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

    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        SecretMigration.migrateUserDefaultsTokensToKeychainIfNeeded()

        setupStatusItem()

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
            self.conversationStore.addMessage(to: uuid, role: .assistant, content: content)
        }

        agentBridge.onStreamChunk = { [weak self] conversationId, content in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }

            if let conversation = self.conversationStore.conversations.first(where: { $0.id == uuid }),
               conversation.messages.last?.role == .assistant {
                self.conversationStore.appendToLastAssistantMessage(in: uuid, chunk: content)
            } else {
                self.conversationStore.addMessage(to: uuid, role: .assistant, content: content)
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
    }

    private func handleToolRequest(toolName: String, input: [String: Any]) async -> String {
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

        case "read_selected_text":
            return await accessibilityReader.readSelectedText() ?? "No text selected"

        case "execute_applescript":
            let script = input["script"] as? String ?? ""
            return toolRunner.executeAppleScript(script)

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

        default:
            return "Unknown tool: \(toolName)"
        }
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
}
