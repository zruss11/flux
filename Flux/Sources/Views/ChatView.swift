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
    @FocusState private var isInputFocused: Bool
    @State private var showMicPermissionAlert = false
    @State private var showSpeechPermissionAlert = false
    @State private var sttFailureMessage: String?
    @State private var worktreeEnabled = false
    @State private var showBranchPicker = false
    @State private var availableBranches: [String] = []
    @State private var branchCheckoutErrorMessage: String?
    @State private var imageImportErrorMessage: String?
    @State private var pendingImageAttachments: [MessageImageAttachment] = []

    private let maxAttachmentBytes = 10 * 1024 * 1024

    private let shareScreenFileName = "__flux_screenshot.jpg"

    private var speechInputProvider: SpeechInputProvider {
        SpeechInputProvider(rawValue: speechInputProviderRaw) ?? .apple
    }

    private var canSendMessage: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImageAttachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // "Pick up where you left off" pill when chat is empty
            if conversationStore.activeConversation?.messages.isEmpty ?? true,
               let recent = SessionContextManager.shared.historyStore.sessions.first {
                RecentContextPill(session: recent) {
                    inputText = "What was I doing in \(recent.appName)?"
                    if let windowTitle = recent.windowTitle, !windowTitle.isEmpty {
                        inputText += " The window was titled \"\(windowTitle)\"."
                    }
                    sendMessage()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let conversation = conversationStore.activeConversation {
                            ForEach(conversation.displaySegments) { segment in
                                Group {
                                    switch segment {
                                    case .userMessage(let message):
                                        MessageBubble(message: message)
                                    case .assistantText(let message):
                                        MessageBubble(message: message)
                                    case .toolCallGroup(_, let calls):
                                        ToolCallGroupView(calls: calls)
                                    }
                                }
                                .id(segment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: conversationStore.scrollRevision) { _, _ in
                    guard conversationStore.lastScrollConversationId == conversationStore.activeConversationId,
                          let conversation = conversationStore.activeConversation,
                          let lastSegment = conversation.displaySegments.last else { return }
                    withAnimation {
                        scrollProxy.scrollTo(lastSegment.id, anchor: .bottom)
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

                HStack(spacing: 8) {
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
                                    mode: .live,
                                    provider: speechInputProvider,
                                    onComplete: { transcript in
                                        inputText = DictionaryCorrector.apply(transcript, using: CustomDictionaryStore.shared.entries)
                                        sendMessage()
                                    },
                                    onFailure: { reason in
                                        if !reason.isEmpty {
                                            sttFailureMessage = reason
                                        }
                                    }
                                )
                                if !started {
                                    if speechInputProvider.requiresSpeechRecognitionPermission &&
                                       SFSpeechRecognizer.authorizationStatus() != .authorized {
                                        showSpeechPermissionAlert = true
                                    }
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

                    TextField("Message Flux…  $ skills  / commands", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
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

                // Git branch pill
                if let branch = GitBranchMonitor.shared.currentBranch {
                    Button {
                        Task {
                            await GitBranchMonitor.shared.fetchBranches()
                            availableBranches = GitBranchMonitor.shared.branches
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
                        .fixedSize()
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
                            branches: availableBranches,
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
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ChatContentHeightKey.self, value: geo.size.height)
            }
        )
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
        }
        .onChange(of: conversationStore.workspacePath) { _, newPath in
            GitBranchMonitor.shared.monitor(workspacePath: newPath)
        }
        .onChange(of: voiceInput.transcript) { _, newValue in
            // While recording, show partial (live) transcription as the user speaks.
            guard voiceInput.isRecording else { return }
            inputText = newValue
        }
        .onChange(of: conversationStore.activeConversationId) { _, _ in
            inputText = ""
            selectedSkillDirNames.removeAll()
            worktreeEnabled = false
            conversationStore.activeWorktreeBranch = nil
            pendingImageAttachments.removeAll()
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
            let conversation = conversationStore.createConversation()
            conversationId = conversation.id
        }

        // Display what the user typed (with `$skill`), but send `/skill` to the sidecar.
        conversationStore.addMessage(to: conversationId, role: .user, content: text, imageAttachments: pendingImageAttachments)
        conversationStore.setConversationRunning(conversationId, isRunning: true)
        agentBridge.sendChatMessage(
            conversationId: conversationId.uuidString,
            content: outboundText,
            images: pendingImageAttachments.map(\.chatPayload)
        )

        inputText = ""
        selectedSkillDirNames.removeAll()
        pendingImageAttachments.removeAll()
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
