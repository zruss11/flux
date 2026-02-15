import SwiftUI
import Foundation
import os

@main
struct FluxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Settings now live entirely inside IslandView.
            CommandGroup(replacing: .appSettings) { }
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

    private let automationService = AutomationService.shared
    private let dictationManager = DictationManager.shared
    private let clipboardMonitor = ClipboardMonitor.shared
    private let watcherService = WatcherService.shared
    private let watcherAlertsConversationId = UUID(uuidString: "5F9E3C52-8A47-4F9D-9C39-CFFB2E7F2A11")!

    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var functionKeyMonitor: EventMonitor?
    private var isFunctionKeyPressed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Flux launching — build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev", privacy: .public)")
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
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.title = "Welcome to Flux"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    private func launchMainApp() {
        Log.app.info("Launching main app — connecting bridge")
        setupBridgeCallbacks()
        setupWatcherCallbacks()
        setupFunctionKeyMonitor()
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

        // Start monitoring frontmost app changes and forward to sidecar.
        let appMonitor = AppMonitor.shared
        appMonitor.onActiveAppChanged = { [weak self] activeApp in
            let instruction = AppInstructions.shared.instruction(forBundleId: activeApp.bundleId)
            self?.agentBridge.sendActiveAppUpdate(
                appName: activeApp.appName,
                bundleId: activeApp.bundleId,
                pid: activeApp.pid,
                appInstruction: instruction?.instruction
            )
        }
        appMonitor.start()

        // If per-app instructions change while Flux is active, immediately resend the current app context.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppInstructionsDidChange(_:)),
            name: .appInstructionsDidChange,
            object: nil
        )

        IslandWindowManager.shared.showIsland(
            conversationStore: conversationStore,
            agentBridge: agentBridge,
            screenCapture: screenCapture
        )

        dictationManager.start(accessibilityReader: accessibilityReader)

        // Register default values for Parakeet transcription settings.
        UserDefaults.standard.register(defaults: [
            "dictationEngine": "apple",
            "asrEnableFragmentRepair": true,
            "asrEnableIntentCorrection": true,
            "asrEnableRepeatRemoval": true,
            "asrEnableNumberConversion": true,
        ])

        // Preload Parakeet models if they are already cached on disk.
        ParakeetModelManager.shared.preloadIfNeeded()

        SessionContextManager.shared.start()
        clipboardMonitor.start()
        watcherService.startAll()
        CIStatusMonitor.shared.start()

        // DEBUG: Cmd+Shift+D triggers a test ticker notification.
        #if DEBUG
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+D
            if event.modifierFlags.contains([.command, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "d" {
                let samples = [
                    "✅ tixbit-monorepo — all checks passed on PR #455",
                    "❌ flux CI failed on branch feature/ticker-bar",
                    "🚀 monorepo deploy pipeline green — ship it!",
                    "✅ san-juan build passed · 42s",
                ]
                let msg = samples.randomElement() ?? samples[0]
                IslandWindowManager.shared.showTickerNotification(msg)
                return nil  // consume the event
            }
            return event
        }
        #endif

        // Auto-start tour on first launch after permissions are granted
        if !UserDefaults.standard.bool(forKey: "hasCompletedTour") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                IslandWindowManager.shared.expand()
                NotificationCenter.default.post(name: .islandStartTourRequested, object: nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("Flux terminating")
        functionKeyMonitor?.stop()
        functionKeyMonitor = nil
        NotificationCenter.default.removeObserver(
            self,
            name: .appInstructionsDidChange,
            object: nil
        )
        dictationManager.stop()
        AppMonitor.shared.stop()
        SessionContextManager.shared.stop()
        clipboardMonitor.stop()
        watcherService.onChatAlert = nil
        CIStatusMonitor.shared.stop()
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

    private func setupFunctionKeyMonitor() {
        functionKeyMonitor?.stop()
        functionKeyMonitor = EventMonitor(mask: .flagsChanged) { [weak self] event in
            self?.handleFunctionKeyFlagsChanged(event)
        }
        functionKeyMonitor?.start()
    }

    private func handleFunctionKeyFlagsChanged(_ event: NSEvent) {
        let isFunctionPressedNow = event.modifierFlags.contains(.function)
        if isFunctionPressedNow {
            guard !isFunctionKeyPressed else { return }
            isFunctionKeyPressed = true
            openExpandedIslandChatView()
            return
        }

        isFunctionKeyPressed = false
    }

    private func openExpandedIslandChatView() {
        let islandWasShown = IslandWindowManager.shared.isShown
        if !islandWasShown {
            IslandWindowManager.shared.showIsland(
                conversationStore: conversationStore,
                agentBridge: agentBridge,
                screenCapture: screenCapture
            )
        }

        let conversationId: UUID
        if let activeConversationId = conversationStore.activeConversationId {
            conversationId = activeConversationId
        } else {
            conversationId = conversationStore.createConversation().id
        }

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

    @objc
    private func handleAppInstructionsDidChange(_ notification: Notification) {
        let activeApp = AppMonitor.shared.currentApp ?? AppMonitor.shared.recentApps.first
        guard let activeApp else { return }
        let instruction = AppInstructions.shared.instruction(forBundleId: activeApp.bundleId)
        agentBridge.sendActiveAppUpdate(
            appName: activeApp.appName,
            bundleId: activeApp.bundleId,
            pid: activeApp.pid,
            appInstruction: instruction?.instruction
        )
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
                agentBridge: agentBridge,
                screenCapture: screenCapture
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
            IslandWindowManager.shared.showIsland(conversationStore: conversationStore, agentBridge: agentBridge, screenCapture: screenCapture)
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

        agentBridge.onSessionInfo = { conversationId, sessionId in
            guard let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                Log.bridge.debug("Sidecar session initialized for conversation \(uuid, privacy: .public): sessionId=\(sessionId, privacy: .public)")
            }
        }

        agentBridge.onForkConversationResult = { [weak self] conversationId, success, reason in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                if success {
                    Log.bridge.info("Fork succeeded for conversation \(uuid, privacy: .public)")
                } else {
                    Log.bridge.warning("Fork failed for conversation \(uuid, privacy: .public): \(reason ?? "unknown", privacy: .public)")
                    self.conversationStore.deleteConversation(id: uuid)
                }
            }
        }

        agentBridge.onPermissionRequest = { [weak self] conversationId, requestId, toolName, input in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                let request = PendingPermissionRequest(id: requestId, toolName: toolName, input: input)
                self.conversationStore.addPermissionRequest(to: uuid, request: request)
            }
        }

        agentBridge.onAskUserQuestion = { [weak self] conversationId, requestId, rawQuestions in
            guard let self, let uuid = UUID(uuidString: conversationId) else { return }
            Task { @MainActor in
                var questions: [PendingAskUserQuestion.Question] = []
                for raw in rawQuestions {
                    guard let questionText = raw["question"] as? String else { continue }
                    let rawOptions = raw["options"] as? [[String: Any]] ?? []
                    var options = rawOptions.compactMap { opt -> PendingAskUserQuestion.Question.Option? in
                        guard let label = opt["label"] as? String else { return nil }
                        return PendingAskUserQuestion.Question.Option(
                            label: label,
                            description: opt["description"] as? String
                        )
                    }
                    let hasOther = options.contains { option in
                        option.label.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                            .hasPrefix("other")
                    }
                    if !hasOther {
                        options.append(PendingAskUserQuestion.Question.Option(label: "Other", description: nil))
                    }
                    let multiSelect = raw["multiSelect"] as? Bool ?? false
                    questions.append(PendingAskUserQuestion.Question(
                        question: questionText,
                        options: options,
                        multiSelect: multiSelect
                    ))
                }
                guard !questions.isEmpty else { return }
                let pending = PendingAskUserQuestion(id: requestId, questions: questions)
                self.conversationStore.addAskUserQuestion(to: uuid, question: pending)
            }
        }
    }

    private func setupWatcherCallbacks() {
        watcherService.onChatAlert = { [weak self] alert in
            guard let self else { return }
            Task { @MainActor in
                self.routeWatcherAlertToChat(alert)
            }
        }
    }

    private func routeWatcherAlertToChat(_ alert: WatcherAlert) {
        let conversation = conversationStore.ensureConversationExists(
            id: watcherAlertsConversationId,
            title: "Watcher Alerts"
        )

        var content = "[\(alert.watcherName)] \(alert.title)\n\n\(alert.summary)"
        if let sourceUrl = alert.sourceUrl, !sourceUrl.isEmpty {
            content += "\n\nSource: \(sourceUrl)"
        }

        conversationStore.addMessage(
            to: conversation.id,
            role: .system,
            content: content
        )
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
            let highlightCaret = input["highlight_caret"] as? Bool ?? false
            let caretRect: CGRect? = highlightCaret ? accessibilityReader.getCaretBounds() : nil
            if target == "window" {
                return await screenCapture.captureFrontmostWindow(caretRect: caretRect) ?? "Failed to capture window"
            } else {
                return await screenCapture.captureMainDisplay(caretRect: caretRect) ?? "Failed to capture display"
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

        case "set_worktree":
            let rawBranchName = (input["branchName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let branchName = (rawBranchName?.isEmpty == true) ? nil : rawBranchName
            conversationStore.activeWorktreeBranch = branchName
            return encodeJSON(SetWorktreeResponse(ok: true, branchName: branchName))

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

        case "read_session_history":
            let appName = input["appName"] as? String
            let limit = intInput("limit") ?? 10
            let sessions = SessionContextManager.shared.historyStore.recentSessions(appName: appName, limit: limit)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(sessions), let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "Failed to read session history"

        case "get_session_context_summary":
            let limit = intInput("limit") ?? 10
            return SessionContextManager.shared.historyStore.contextSummaryText(limit: limit)

        case "read_clipboard_history":
            let rawLimit = intInput("limit") ?? 10
            let limit = min(max(rawLimit, 0), 10)
            let entries = Array(ClipboardMonitor.shared.store.entries.prefix(limit))
            return encodeJSON(ClipboardHistoryResponse(ok: true, entries: entries))

        case "check_github_status":
            let repo = (input["repo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return await checkGitHubStatus(repo: repo)

        case "manage_github_repos":
            let action = (input["action"] as? String ?? "list").lowercased()
            let repo = (input["repo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return manageGitHubRepos(action: action, repo: repo)

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

    private struct SetWorktreeResponse: Codable {
        let ok: Bool
        let branchName: String?
    }

    private struct ClipboardHistoryResponse: Codable {
        let ok: Bool
        let entries: [ClipboardEntry]
    }

    private struct GitHubReposResponse: Codable {
        let ok: Bool
        let repos: [String]
        let message: String?
    }

    private func manageGitHubRepos(action: String, repo: String) -> String {
        let key = "githubWatchedRepos"
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        var repos = raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch action {
        case "add":
            guard !repo.isEmpty else {
                return encodeJSON(GitHubReposResponse(ok: false, repos: repos, message: "Missing repo parameter."))
            }
            if repos.contains(repo) {
                return encodeJSON(GitHubReposResponse(ok: true, repos: repos, message: "Repo '\(repo)' is already watched."))
            }
            repos.append(repo)
            let joined = repos.joined(separator: ",")
            UserDefaults.standard.set(joined, forKey: key)
            WatcherService.shared.updateGitHubRepos(joined)
            CIStatusMonitor.shared.forceRefresh()
            return encodeJSON(GitHubReposResponse(ok: true, repos: repos, message: "Added '\(repo)'."))

        case "remove":
            guard !repo.isEmpty else {
                return encodeJSON(GitHubReposResponse(ok: false, repos: repos, message: "Missing repo parameter."))
            }
            guard repos.contains(repo) else {
                return encodeJSON(GitHubReposResponse(ok: false, repos: repos, message: "Repo '\(repo)' is not in the watch list."))
            }
            repos.removeAll { $0 == repo }
            let joined = repos.joined(separator: ",")
            UserDefaults.standard.set(joined, forKey: key)
            WatcherService.shared.updateGitHubRepos(joined)
            CIStatusMonitor.shared.forceRefresh()
            return encodeJSON(GitHubReposResponse(ok: true, repos: repos, message: "Removed '\(repo)'."))

        default: // "list"
            return encodeJSON(GitHubReposResponse(ok: true, repos: repos, message: nil))
        }
    }

    // MARK: - GitHub Status (gh CLI)

    private struct GitHubStatusAlert: Codable {
        let type: String   // "ci" or "notification"
        let title: String
        let repo: String
        let branch: String?
        let status: String?
        let url: String
        let updatedAt: String
    }

    private struct GitHubStatusResponse: Codable {
        let ok: Bool
        let authenticated: Bool
        let alerts: [GitHubStatusAlert]
        let error: String?
    }

    private func checkGitHubStatus(repo: String?) async -> String {
        // Verify gh CLI is authenticated
        let authResult = await shellGH(["auth", "status", "--active"])
        guard authResult.exitCode == 0 else {
            return encodeJSON(GitHubStatusResponse(
                ok: false,
                authenticated: false,
                alerts: [],
                error: "gh CLI not authenticated. Run `gh auth login` in terminal."
            ))
        }

        var alerts: [GitHubStatusAlert] = []

        // 1. Check CI failures
        var runArgs = ["run", "list", "--status", "failure", "--limit", "10",
                       "--json", "databaseId,name,headBranch,updatedAt,conclusion,url,workflowName"]
        if let repo = repo, !repo.isEmpty {
            runArgs += ["--repo", repo]
        }
        let ciResult = await shellGH(runArgs)
        if ciResult.exitCode == 0, !ciResult.output.isEmpty,
           let data = ciResult.output.data(using: .utf8),
           let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for run in runs {
                let name = run["workflowName"] as? String ?? run["name"] as? String ?? "Workflow"
                let branch = run["headBranch"] as? String
                let conclusion = run["conclusion"] as? String ?? "failure"
                let url = run["url"] as? String ?? ""
                let updatedAt = run["updatedAt"] as? String ?? ""

                // Derive repo from the URL: https://github.com/owner/repo/actions/runs/123
                let repoName: String
                if let r = repo {
                    repoName = r
                } else if let urlRepo = extractRepoFromUrl(url) {
                    repoName = urlRepo
                } else {
                    repoName = ""
                }

                alerts.append(GitHubStatusAlert(
                    type: "ci",
                    title: "CI Failed: \(name)",
                    repo: repoName,
                    branch: branch,
                    status: conclusion,
                    url: url,
                    updatedAt: updatedAt
                ))
            }
        }

        // 2. Check recent notifications
        var notifArgs = ["api", "notifications", "--jq", "."]
        if let repo = repo, !repo.isEmpty {
            notifArgs += ["-f", "all=false"]
        }
        let notifResult = await shellGH(notifArgs)
        if notifResult.exitCode == 0, !notifResult.output.isEmpty,
           let data = notifResult.output.data(using: .utf8),
           let notifications = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for notif in notifications.prefix(10) {
                guard let subject = notif["subject"] as? [String: Any],
                      let title = subject["title"] as? String,
                      let repoObj = notif["repository"] as? [String: Any],
                      let repoFullName = repoObj["full_name"] as? String else { continue }

                // If repo filter is specified, skip non-matching notifications
                if let filterRepo = repo, !filterRepo.isEmpty,
                   !repoFullName.lowercased().contains(filterRepo.lowercased()) {
                    continue
                }

                let updatedAt = notif["updated_at"] as? String ?? ""
                let repoHtmlUrl = repoObj["html_url"] as? String ?? "https://github.com/\(repoFullName)"

                alerts.append(GitHubStatusAlert(
                    type: "notification",
                    title: title,
                    repo: repoFullName,
                    branch: nil,
                    status: notif["reason"] as? String,
                    url: repoHtmlUrl,
                    updatedAt: updatedAt
                ))
            }
        }

        return encodeJSON(GitHubStatusResponse(
            ok: true,
            authenticated: true,
            alerts: alerts,
            error: nil
        ))
    }

    /// Extract owner/repo from a GitHub actions URL.
    private func extractRepoFromUrl(_ url: String) -> String? {
        // https://github.com/owner/repo/actions/runs/12345
        guard let range = url.range(of: #"github\.com/([^/]+/[^/]+)"#, options: .regularExpression) else {
            return nil
        }
        return String(url[range]).replacingOccurrences(of: "github.com/", with: "")
    }

    /// Runs a `gh` CLI command synchronously and returns the output.
    private func shellGH(_ arguments: [String]) async -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        return await withCheckedContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", Int32(1)))
                return
            }

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (output, process.terminationStatus))
            }
        }
    }

}
