import SwiftUI

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

        default:
            return "Unknown tool: \(toolName)"
        }
    }
}
