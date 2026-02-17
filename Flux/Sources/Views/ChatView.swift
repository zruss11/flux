import AppKit
import MarkdownUI
import Speech
import SwiftUI
import UniformTypeIdentifiers

// Preference key to report the chat content's intrinsic height back up the view tree
struct ChatContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Preference key to tell IslandView whether the skills panel is visible
struct SkillsVisibleKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// Preference key to tell IslandView whether there are pending image attachments
struct HasPendingAttachmentsKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ChatView: View {
    private struct ForkContext {
        let sourceConversationId: UUID
        let sourceTitle: String
    }

    @Bindable var conversationStore: ConversationStore
    var agentBridge: AgentBridge
    var screenCapture: ScreenCapture
    @AppStorage(SpeechInputSettings.providerStorageKey) private var speechInputProviderRaw = SpeechInputProvider.apple.rawValue
    @State private var inputText = ""
    @State private var voiceInput = VoiceInput()
    @State private var showSkills = false
    @State private var dollarTriggerActive = false
    @State private var selectedSkillDirNames: Set<String> = []
    @State private var skillSearchQuery = ""
    @State private var showSlashCommands = false
    @State private var slashTriggerActive = false
    @State private var slashSearchQuery = ""
    @State private var watcherService = WatcherService.shared
    @AppStorage("showWatcherAlertsChip") private var showWatcherAlertsChip = true
    @FocusState private var isInputFocused: Bool
    @State private var showMicPermissionAlert = false
    @State private var showSpeechPermissionAlert = false
    @State private var sttFailureMessage: String?
    @State private var worktreeEnabled = false
    @State private var showBranchPicker = false
    @State private var selectedModelSpec: String? = nil
    @State private var showModelPicker = false
    @AppStorage("defaultModelSpec") private var defaultModelSpec = "anthropic:claude-sonnet-4-20250514"

    @State private var branchCheckoutErrorMessage: String?
    @State private var imageImportErrorMessage: String?
    @State private var pendingImageAttachments: [MessageImageAttachment] = []
    @State private var forkBannerVisible = false
    @State private var forkBannerDismissTask: Task<Void, Never>?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var pendingForkContexts: [UUID: ForkContext] = [:]
    @State private var visibleSegmentLimit = 60

    private let maxAttachmentBytes = 10 * 1024 * 1024
    private let initialVisibleSegmentLimit = 60
    private let segmentLoadStep = 100

    private let shareScreenFileName = "__flux_screenshot.jpg"

    private var speechInputProvider: SpeechInputProvider {
        SpeechInputProvider(rawValue: speechInputProviderRaw) ?? .apple
    }

    private var canSendMessage: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImageAttachments.isEmpty
    }

    private var isModelLocked: Bool {
        guard let conversation = conversationStore.activeConversation else { return false }
        return !conversation.messages.isEmpty
    }

    private var activeWatcherAlerts: [WatcherAlert] {
        watcherService.alerts.filter { !$0.isDismissed }
    }

    private var visibleSegments: [DisplaySegment] {
        guard let conversation = conversationStore.activeConversation else { return [] }
        return conversation.displaySegmentsTail(limit: visibleSegmentLimit)
    }

    private var isActiveConversationRunning: Bool {
        guard let conversationId = conversationStore.activeConversationId else { return false }
        return conversationStore.isConversationRunning(conversationId)
    }


    var body: some View {
        let displayedSegments = visibleSegments
        let totalSegmentCount = conversationStore.activeConversation?.displaySegmentCount ?? 0
        let hiddenSegments = max(totalSegmentCount - displayedSegments.count, 0)
        let isConversationEmpty = conversationStore.activeConversation?.messages.isEmpty ?? true

        VStack(spacing: 0) {
            // At a Glance cards when chat is empty
            if isConversationEmpty {
                AtAGlanceView(
                    conversationStore: conversationStore,
                    onPromptAction: { prompt in
                        inputText = prompt
                        sendMessage()
                    },
                    onOpenConversation: { conversationId in
                        conversationStore.openConversation(id: conversationId)
                    },
                    onOpenWorktree: { snapshot in
                        openWorktreeConversation(snapshot)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Messages
            if !isConversationEmpty {
                ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if hiddenSegments > 0 {
                            Button {
                                visibleSegmentLimit += segmentLoadStep
                            } label: {
                                Text("Load \(min(segmentLoadStep, hiddenSegments)) earlier updates")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        ForEach(displayedSegments) { segment in
                            Group {
                                switch segment {
                                case .userMessage(let message):
                                    MessageBubble(message: message)
                                case .assistantText(let message):
                                    if message.role == .system {
                                        ForkIndicatorView(content: message.content)
                                    } else {
                                        MessageBubble(message: message)
                                    }
                                case .toolCallGroup(_, let calls):
                                    ToolCallGroupView(calls: calls)
                                case .permissionRequest(let req):
                                    PermissionApprovalCard(request: req) {
                                        guard let convId = conversationStore.activeConversationId else { return }
                                        conversationStore.resolvePermissionRequest(
                                            in: convId,
                                            requestId: req.id,
                                            approved: true
                                        )
                                        agentBridge.sendPermissionResponse(requestId: req.id, behavior: "allow")
                                    } onDeny: {
                                        guard let convId = conversationStore.activeConversationId else { return }
                                        conversationStore.resolvePermissionRequest(
                                            in: convId,
                                            requestId: req.id,
                                            approved: false
                                        )
                                        agentBridge.sendPermissionResponse(requestId: req.id, behavior: "deny", message: "User denied this action")
                                    }
                                case .askUserQuestion(let q):
                                    AskUserQuestionCard(question: q) { answers in
                                        guard let convId = conversationStore.activeConversationId else { return }
                                        conversationStore.resolveAskUserQuestion(
                                            in: convId,
                                            requestId: q.id,
                                            answers: answers
                                        )
                                        agentBridge.sendPermissionResponse(
                                            requestId: q.id,
                                            behavior: "allow",
                                            answers: answers
                                        )
                                    }
                                case .subAgentGroup(let activity):
                                    SubAgentGroupView(activity: activity)
                                }
                            }
                            .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ChatContentHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .overlay(alignment: .top) {
                    if forkBannerVisible {
                        ForkSuccessBanner()
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .padding(.top, 8)
                    }
                }
                .onChange(of: conversationStore.scrollRevision) { _, _ in
                    // Avoid expensive off-screen ScrollViewReader work while the island is collapsed.
                    guard IslandWindowManager.shared.isExpanded else { return }
                    guard conversationStore.lastScrollConversationId == conversationStore.activeConversationId,
                          let lastSegment = displayedSegments.last else { return }

                    autoScrollTask?.cancel()
                    let targetId = lastSegment.id
                    let shouldAnimate = !isActiveConversationRunning

                    autoScrollTask = Task { @MainActor in
                        // While streaming, coalesce frequent chunk updates into a single
                        // scroll operation to avoid saturating the main thread.
                        if !shouldAnimate {
                            try? await Task.sleep(for: .milliseconds(120))
                            guard !Task.isCancelled else { return }
                            scrollProxy.scrollTo(targetId, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                scrollProxy.scrollTo(targetId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            }

            // Input row
            VStack(alignment: .leading, spacing: 8) {
                if !pendingImageAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingImageAttachments) { attachment in
                                ImageAttachmentPreviewCard(attachment: attachment, isRemovable: true) {
                                    pendingImageAttachments.removeAll { $0.id == attachment.id }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    // Mic button
                    Button {
                        Task {
                            if voiceInput.isRecording {
                                voiceInput.stopRecording()
                            } else {
                                let granted = await voiceInput.ensureMicrophonePermission()
                                guard granted else {
                                    showMicPermissionAlert = true
                                    return
                                }
                                let started = await voiceInput.startRecording(
                                    mode: speechInputProvider.voiceInputMode,
                                    provider: speechInputProvider,
                                    onComplete: { transcript in
                                        inputText = TranscriptPostProcessor.process(transcript)
                                        sendMessage()
                                    },
                                    onFailure: { reason in
                                        if !reason.isEmpty {
                                            sttFailureMessage = reason
                                        }
                                    }
                                )
                                if !started && speechInputProvider != .deepgram && SFSpeechRecognizer.authorizationStatus() != .authorized {
                                    showSpeechPermissionAlert = true
                                }
                            }
                        }
                    } label: {
                        Image(systemName: voiceInput.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 14))
                            .foregroundStyle(voiceInput.isRecording ? .red : .white.opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    // Multi-line input with height driven by content (1–3 lines)
                    Text(inputText.isEmpty ? " " : inputText)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0)
                        .overlay(alignment: .topLeading) {
                            // Placeholder
                            if inputText.isEmpty {
                                Text("Message Flux…  $ skills  / commands")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            TextEditor(text: $inputText)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .scrollIndicators(.hidden)
                                .contentMargins(.all, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .focused($isInputFocused)
                                .onKeyPress(.return) {
                                    if NSEvent.modifierFlags.contains(.shift) {
                                        return .ignored
                                    }
                                    sendMessage()
                                    return .handled
                                }
                                .onKeyPress(.escape) {
                                    if showSlashCommands {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                            showSlashCommands = false
                                        }
                                        return .handled
                                    }
                                    if showSkills {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                            showSkills = false
                                        }
                                        return .handled
                                    }
                                    if IslandWindowManager.shared.isExpanded {
                                        IslandWindowManager.shared.collapse()
                                        return .handled
                                    }
                                    return .ignored
                                }
                        }

                    Button {
                        NotificationCenter.default.post(name: .islandOpenImagePickerRequested, object: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canSendMessage ? .white : .white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendMessage)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)

            // Slash commands list appears below the input
            if showSlashCommands {
                SlashCommandsView(
                    isPresented: $showSlashCommands,
                    searchQuery: $slashSearchQuery,
                    workspacePath: conversationStore.workspacePath
                ) { cmd in
                    insertSlashCommand(cmd)
                    isInputFocused = true
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }

            // Skills list appears below the input, expanding the window downward
            if showSkills {
                SkillsView(isPresented: $showSkills, searchQuery: $skillSearchQuery, showsPill: false) { skill in
                    insertSkillToken(skill.directoryName)
                    isInputFocused = true
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }

            // Workspace folder picker + Skills pill on the same line
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .islandOpenFolderPickerRequested, object: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(conversationStore.workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Select workspace...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // Model selector pill
                ModelSelectorPill(
                    selectedModelSpec: selectedModelSpec,
                    isLocked: isModelLocked,
                    availableProviders: agentBridge.availableProviders,
                    defaultModelSpec: defaultModelSpec,
                    onSelect: { spec in
                        selectedModelSpec = spec
                    }
                )

                // Git branch pill
                if let branch = GitBranchMonitor.shared.currentBranch {
                    Button {
                        Task {
                            await GitBranchMonitor.shared.fetchBranches()
                            showBranchPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(branch)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) {
                        GitBranchPickerPopover(
                            branches: GitBranchMonitor.shared.branches,
                            currentBranch: branch
                        ) { selected in
                            showBranchPicker = false
                            Task {
                                let didCheckout = await GitBranchMonitor.shared.checkout(selected)
                                if !didCheckout {
                                    branchCheckoutErrorMessage = "Couldn't switch to \"\(selected)\". Resolve git conflicts or uncommitted changes, then try again."
                                }
                            }
                        }
                    }
                }

                Button {
                    if conversationStore.activeWorktreeBranch != nil {
                        conversationStore.activeWorktreeBranch = nil
                        worktreeEnabled = false
                    } else {
                        worktreeEnabled.toggle()
                    }
                } label: {
                    let isActive = worktreeEnabled || conversationStore.activeWorktreeBranch != nil
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                        Text(conversationStore.activeWorktreeBranch ?? "Worktree")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isActive ? 0.15 : 0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(isActive ? 0.2 : 0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                if showWatcherAlertsChip, !activeWatcherAlerts.isEmpty {
                    WatcherAlertsChip(
                        activeAlerts: activeWatcherAlerts,
                        onDismissAll: {
                            watcherService.dismissAllAlerts()
                        },
                        onOpenSettings: {
                            NotificationCenter.default.post(name: .islandOpenSettingsRequested, object: nil)
                        },
                        onHide: {
                            showWatcherAlertsChip = false
                        }
                    )
                }

                // Fork conversation pill
                if conversationStore.activeConversationId != nil,
                   !(conversationStore.activeConversation?.messages.isEmpty ?? true) {
                    Button {
                        forkCurrentConversation()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.on.rectangle")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("Fork")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                SkillsPillButton(isPresented: $showSkills)

                Button {
                    Task {
                        let hasScreenshot = pendingImageAttachments.contains { $0.fileName == shareScreenFileName }
                        if hasScreenshot {
                            pendingImageAttachments.removeAll { $0.fileName == shareScreenFileName }
                        } else {
                            if let base64 = await screenCapture.captureMainDisplay() {
                                let attachment = MessageImageAttachment(
                                    fileName: shareScreenFileName,
                                    mediaType: "image/jpeg",
                                    base64Data: base64
                                )
                                pendingImageAttachments.append(attachment)
                            }
                        }
                    }
                } label: {
                    let isActive = pendingImageAttachments.contains { $0.fileName == shareScreenFileName }
                    HStack(spacing: 4) {
                        Image(systemName: "display")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                        Text("Share Screen")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.6))
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isActive ? 0.15 : 0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(isActive ? 0.2 : 0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
            .defaultScrollAnchor(.leading)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .preference(key: SkillsVisibleKey.self, value: showSkills || showSlashCommands)
        .preference(key: HasPendingAttachmentsKey.self, value: !pendingImageAttachments.isEmpty)
        .onChange(of: inputText) { oldValue, newValue in
            // --- Slash command trigger: `/` at the start of input ---
            if newValue.hasPrefix("/") && !oldValue.hasPrefix("/") {
                slashTriggerActive = true
                if !showSlashCommands {
                    // Dismiss skills if open
                    if showSkills {
                        showSkills = false
                        dollarTriggerActive = false
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        showSlashCommands = true
                    }
                }
                slashSearchQuery = ""
            }

            // Update slash search query
            if showSlashCommands, slashTriggerActive, newValue.hasPrefix("/") {
                slashSearchQuery = String(newValue.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Dismiss slash commands if `/` prefix was removed
            if showSlashCommands, slashTriggerActive, !newValue.hasPrefix("/") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showSlashCommands = false
                }
            }

            // --- Dollar skill trigger ---
            // Detect a freshly typed `$` to open skills (or re-activate search if already open)
            if newValue.count - oldValue.count == 1,
               newValue.filter({ $0 == "$" }).count > oldValue.filter({ $0 == "$" }).count {
                dollarTriggerActive = true
                if !showSkills {
                    // Dismiss slash commands if open
                    if showSlashCommands {
                        showSlashCommands = false
                        slashTriggerActive = false
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        showSkills = true
                    }
                }
                skillSearchQuery = ""
            }

            // Update the search query with whatever is typed after the last `$`
            if showSkills, dollarTriggerActive, let idx = newValue.lastIndex(of: "$") {
                let afterDollar = String(newValue[newValue.index(after: idx)...])
                skillSearchQuery = afterDollar.trimmingCharacters(in: .whitespaces)
            }

            // Dismiss skills if the trigger `$` was deleted
            if showSkills, dollarTriggerActive, !newValue.contains("$") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    showSkills = false
                }
            }
        }
        .onChange(of: showSkills) { _, presented in
            if !presented {
                dollarTriggerActive = false
                skillSearchQuery = ""
            }
        }
        .onChange(of: showSlashCommands) { _, presented in
            if !presented {
                slashTriggerActive = false
                slashSearchQuery = ""
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
            GitBranchMonitor.shared.monitor(workspacePath: conversationStore.workspacePath)
            agentBridge.onForkConversationResult = { conversationId, success, _ in
                guard let uuid = UUID(uuidString: conversationId) else { return }
                Task { @MainActor in
                    handleForkConversationResult(conversationId: uuid, success: success)
                }
            }
        }
        .onDisappear {
            forkBannerDismissTask?.cancel()
            autoScrollTask?.cancel()
        }
        .onChange(of: conversationStore.workspacePath) { _, newPath in
            GitBranchMonitor.shared.monitor(workspacePath: newPath)
        }
        .onChange(of: voiceInput.transcript) { _, newValue in
            // While recording, show partial (live) transcription as the user speaks.
            guard voiceInput.isRecording else { return }
            inputText = newValue
        }
        .onChange(of: conversationStore.activeConversationId) { _, newConversationId in
            autoScrollTask?.cancel()
            inputText = ""
            visibleSegmentLimit = initialVisibleSegmentLimit
            selectedSkillDirNames.removeAll()
            worktreeEnabled = false
            pendingImageAttachments.removeAll()
            selectedModelSpec = conversationStore.activeConversation?.modelSpec
            if let newConversationId,
               let worktreeBranch = conversationStore.worktreeBranch(for: newConversationId) {
                conversationStore.activeWorktreeBranch = worktreeBranch
            } else {
                conversationStore.activeWorktreeBranch = nil
            }
            if showSkills {
                showSkills = false
                dollarTriggerActive = false
            }
            if showSlashCommands {
                showSlashCommands = false
                slashTriggerActive = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandImageFilesSelected)) { notification in
            guard let urls = notification.userInfo?[NotificationPayloadKey.imageURLs] as? [URL] else { return }
            for url in urls {
                do {
                    let attachment = try loadImageAttachment(from: url)
                    pendingImageAttachments.append(attachment)
                } catch {
                    imageImportErrorMessage = error.localizedDescription
                    return
                }
            }
        }

        .alert("Microphone Access Required", isPresented: $showMicPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Flux needs microphone access for voice input. Please enable it in System Settings > Privacy & Security > Microphone.")
        }
        .alert("Speech Recognition Access Required", isPresented: $showSpeechPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Flux needs Speech Recognition access for on-device transcription. Please enable it in System Settings > Privacy & Security > Speech Recognition.")
        }
        .alert("Speech Input Error", isPresented: Binding(
            get: { sttFailureMessage != nil },
            set: { shown in
                if !shown {
                    sttFailureMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                sttFailureMessage = nil
            }
        } message: {
            Text(sttFailureMessage ?? "Unable to start speech input.")
        }
        .alert("Image Import Failed", isPresented: Binding(
            get: { imageImportErrorMessage != nil },
            set: { shown in
                if !shown { imageImportErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                imageImportErrorMessage = nil
            }
        } message: {
            Text(imageImportErrorMessage ?? "Unable to add image.")
        }
        .alert("Branch Switch Failed", isPresented: Binding(
            get: { branchCheckoutErrorMessage != nil },
            set: { shown in
                if !shown { branchCheckoutErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                branchCheckoutErrorMessage = nil
            }
        } message: {
            Text(branchCheckoutErrorMessage ?? "Unable to switch branches.")
        }
    }

    private func openWorktreeConversation(_ snapshot: WorktreeSnapshot) {
        if conversationStore.workspacePath != snapshot.path {
            conversationStore.workspacePath = snapshot.path
        }

        if let existingConversationId = conversationStore.conversationId(forWorktreeBranch: snapshot.branch) {
            conversationStore.openConversation(id: existingConversationId)
            conversationStore.activeWorktreeBranch = snapshot.branch
            return
        }

        let effectiveModelSpec = selectedModelSpec ?? defaultModelSpec
        let conversation = conversationStore.createConversation(modelSpec: effectiveModelSpec)
        let title = conversationStore.worktreeTaskTitle(for: snapshot.branch) ?? snapshot.branch
        conversationStore.renameConversation(id: conversation.id, to: title)
        conversationStore.bindWorktreeBranch(snapshot.branch, to: conversation.id, title: title)
        conversationStore.activeWorktreeBranch = snapshot.branch
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImageAttachments.isEmpty else { return }

        // Slash commands
        let lowered = text.lowercased()
        if pendingImageAttachments.isEmpty && lowered.hasPrefix("/") {
            let cmdName = String(lowered.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)

            // Local-only commands
            if cmdName == "new" || cmdName == "clear" {
                inputText = ""
                selectedSkillDirNames.removeAll()
                pendingImageAttachments.removeAll()
                if showSkills {
                    showSkills = false
                    dollarTriggerActive = false
                }
                if showSlashCommands {
                    showSlashCommands = false
                    slashTriggerActive = false
                }
                conversationStore.startNewConversation()
                return
            }
        }

        if showSkills {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showSkills = false
            }
            dollarTriggerActive = false
        }
        if showSlashCommands {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showSlashCommands = false
            }
            slashTriggerActive = false
        }

        var outboundText = transformSelectedSkillTokensForOutbound(text)

        if worktreeEnabled && conversationStore.activeWorktreeBranch == nil {
            let worktreePrefix = "Before writing code, create a git worktree for this task outside this repository tree. Choose a short, descriptive branch name based on my request, then run `mkdir -p ~/Applications/FluxWorktrees && git worktree add ~/Applications/FluxWorktrees/<branch-name> -b <branch-name>` and cd into the new worktree before doing any work. After creating the worktree, call the `mcp__flux__set_worktree` tool with the branch name so it appears in the UI.\n\n"
            outboundText = worktreePrefix + outboundText
        }

        var conversationId: UUID
        if let activeId = conversationStore.activeConversationId {
            conversationId = activeId
        } else {
            let effectiveModelSpec = selectedModelSpec ?? defaultModelSpec
            let conversation = conversationStore.createConversation(modelSpec: effectiveModelSpec)
            conversationId = conversation.id
        }

        // Display what the user typed (with `$skill`), but send `/skill` to the sidecar.
        conversationStore.addMessage(to: conversationId, role: .user, content: text, imageAttachments: pendingImageAttachments)
        conversationStore.setConversationRunning(conversationId, isRunning: true)
        let isFirstMessage = conversationStore.activeConversation?.messages.count == 1
        agentBridge.sendChatMessage(
            conversationId: conversationId.uuidString,
            content: outboundText,
            images: pendingImageAttachments.map(\.chatPayload),
            modelSpec: isFirstMessage ? (selectedModelSpec ?? defaultModelSpec) : nil
        )

        inputText = ""
        selectedSkillDirNames.removeAll()
        pendingImageAttachments.removeAll()
    }

    private func forkCurrentConversation() {
        guard let sourceId = conversationStore.activeConversationId else { return }
        forkBannerDismissTask?.cancel()
        forkBannerVisible = false
        let sourceTitle = conversationStore.summaries.first(where: { $0.id == sourceId })?.title ?? "Chat"
        guard let newId = conversationStore.forkConversation(id: sourceId) else { return }
        pendingForkContexts[newId] = ForkContext(
            sourceConversationId: sourceId,
            sourceTitle: sourceTitle
        )

        agentBridge.sendForkConversation(
            sourceConversationId: sourceId.uuidString,
            newConversationId: newId.uuidString
        )
    }

    private func handleForkConversationResult(conversationId: UUID, success: Bool) {
        guard let context = pendingForkContexts.removeValue(forKey: conversationId) else { return }

        guard success else {
            forkBannerDismissTask?.cancel()
            forkBannerVisible = false
            conversationStore.deleteConversation(id: conversationId)
            if conversationStore.activeConversationId == conversationId {
                conversationStore.openConversation(id: context.sourceConversationId)
            }
            return
        }

        conversationStore.addMessage(
            to: conversationId,
            role: .system,
            content: "Forked from \"\(context.sourceTitle)\""
        )

        forkBannerDismissTask?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            forkBannerVisible = true
        }
        forkBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                forkBannerVisible = false
            }
        }
    }

    private func insertSkillToken(_ directoryName: String) {
        let token = "$\(directoryName) "

        if dollarTriggerActive, let idx = inputText.lastIndex(of: "$") {
            // Remove the `$` plus any query text typed after it so the full
            // token replaces the entire `$query` fragment.
            let afterDollar = inputText.index(after: idx)
            let searchEnd = inputText[afterDollar...].firstIndex(where: { $0.isWhitespace }) ?? inputText.endIndex
            let remainder = String(inputText[searchEnd...])
            inputText = String(inputText[..<idx]) + token + remainder.trimmingCharacters(in: .init(charactersIn: " "))
            if !remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                // Ensure a space between the token and any trailing text.
                if !inputText.hasSuffix(" ") {
                    inputText += " "
                }
            }
        } else {
            if let last = inputText.last, !last.isWhitespace {
                inputText.append(" ")
            }
            inputText.append(contentsOf: token)
        }

        selectedSkillDirNames.insert(directoryName)
        dollarTriggerActive = false
        skillSearchQuery = ""
        // Intentionally keep `showSkills` open so users can click multiple skills.
    }

    private func insertSlashCommand(_ cmd: SlashCommand) {
        inputText = "/\(cmd.name) "
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showSlashCommands = false
        }
        slashTriggerActive = false
        slashSearchQuery = ""
    }

    private func transformSelectedSkillTokensForOutbound(_ text: String) -> String {
        guard !selectedSkillDirNames.isEmpty else { return text }

        var out = text
        // Replace longer names first to avoid partial replacement collisions.
        for dir in selectedSkillDirNames.sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: dir)
            let pattern = "(^|\\s)\\$" + escaped + "(?=\\s|$)"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            let safeDir = NSRegularExpression.escapedTemplate(for: dir)
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "$1/\(safeDir)")
        }
        return out
    }

    private func loadImageAttachment(from url: URL) throws -> MessageImageAttachment {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ImageAttachmentImportError.emptyData
        }
        guard data.count <= maxAttachmentBytes else {
            throw ImageAttachmentImportError.fileTooLarge(maxBytes: maxAttachmentBytes)
        }

        let fallbackType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        let mediaType = fallbackType.hasPrefix("image/") ? fallbackType : "image/png"
        return MessageImageAttachment(
            fileName: url.lastPathComponent,
            mediaType: mediaType,
            base64Data: data.base64EncodedString()
        )
    }
}

private enum ImageAttachmentImportError: LocalizedError {
    case emptyData
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyData:
            return "The selected image file is empty."
        case .fileTooLarge(let maxBytes):
            let maxMB = maxBytes / (1024 * 1024)
            return "Image is too large. Max size is \(maxMB)MB."
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 8) {
                if !message.imageAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.imageAttachments) { attachment in
                                ImageAttachmentPreviewCard(attachment: attachment, isRemovable: false, onRemove: nil)
                            }
                        }
                    }
                }

                if message.role == .assistant {
                    MarkdownMessageView(content: message.content)
                } else if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(message.role == .user ? Color.blue.opacity(0.45) : Color.white.opacity(0.12))
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        // Prevent inherited implicit animations (e.g. from IslandView's
        // spring animations) from animating text content, which causes
        // the flicker where text briefly disappears then reappears.
        .transaction { $0.animation = nil }
    }
}

private struct ImageAttachmentPreviewCard: View {
    let attachment: MessageImageAttachment
    let isRemovable: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let image = attachment.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(8)
                }
            }
            .frame(width: 42, height: 42)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("IMAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(0.8)
            }

            if isRemovable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private extension MessageImageAttachment {
    var nsImage: NSImage? {
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return NSImage(data: data)
    }

    var chatPayload: ChatImagePayload {
        ChatImagePayload(fileName: fileName, mediaType: mediaType, data: base64Data)
    }
}

// MARK: - Fork UI Components

/// Animated toast banner that slides in from the top when a conversation is forked.
private struct ForkSuccessBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            Text("Conversation forked successfully")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

/// Inline indicator shown in the conversation history at the fork point.
private struct ForkIndicatorView: View {
    let content: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(content)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .fixedSize()

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
    }
}
