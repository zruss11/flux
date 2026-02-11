import SwiftUI

// Preference key to report the chat content's intrinsic height back up the view tree
struct ChatContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Preference key to signal skills bubble is expanded
struct SkillsExpandedKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ChatView: View {
    @Bindable var conversationStore: ConversationStore
    var agentBridge: AgentBridge
    @State private var inputText = ""
    @State private var voiceInput = VoiceInput()
    @State private var showSkills = false
    @State private var dollarTriggerActive = false
    @State private var selectedSkillDirNames: Set<String> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let conversation = conversationStore.activeConversation {
                            ForEach(conversation.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: conversationStore.activeConversation?.messages.count) { _, _ in
                    if let lastMessage = conversationStore.activeConversation?.messages.last {
                        withAnimation {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input row
            HStack(spacing: 8) {
                // Mic button
                Button {
                    if voiceInput.isRecording {
                        voiceInput.stopRecording()
                    } else {
                        voiceInput.startRecording { transcript in
                            inputText = transcript
                            sendMessage()
                        }
                    }
                } label: {
                    Image(systemName: voiceInput.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(voiceInput.isRecording ? .red : .white.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                TextField("Message Flux...  $ for skills", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(inputText.isEmpty ? .white.opacity(0.2) : .white)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            SkillsView(isPresented: $showSkills) { skill in
                insertSkillToken(skill.directoryName)
                isInputFocused = true
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ChatContentHeightKey.self, value: geo.size.height)
            }
        )
        .preference(key: SkillsExpandedKey.self, value: showSkills)
        .onChange(of: inputText) { oldValue, newValue in
            print("[ChatView] inputText changed: '\(oldValue)' -> '\(newValue)' (delta: \(newValue.count - oldValue.count))")
            if !showSkills,
               newValue.count - oldValue.count == 1,
               newValue.filter({ $0 == "$" }).count > oldValue.filter({ $0 == "$" }).count {
                print("[ChatView] $ detected, opening skills")
                dollarTriggerActive = true
                showSkills = true
            }
        }
        .onChange(of: showSkills) { _, presented in
            if !presented {
                dollarTriggerActive = false
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if showSkills {
            showSkills = false
            dollarTriggerActive = false
        }

        let outboundText = transformSelectedSkillTokensForOutbound(text)

        var conversationId: UUID
        if let activeId = conversationStore.activeConversationId {
            conversationId = activeId
        } else {
            let conversation = conversationStore.createConversation()
            conversationId = conversation.id
        }

        // Display what the user typed (with `$skill`), but send `/skill` to the sidecar.
        conversationStore.addMessage(to: conversationId, role: .user, content: text)
        agentBridge.sendChatMessage(conversationId: conversationId.uuidString, content: outboundText)

        inputText = ""
        selectedSkillDirNames.removeAll()
    }

    private func insertSkillToken(_ directoryName: String) {
        let token = "$\(directoryName) "

        if dollarTriggerActive, let idx = inputText.lastIndex(of: "$") {
            let after = inputText.index(after: idx)
            inputText = String(inputText[..<idx]) + token + String(inputText[after...])
        } else {
            if let last = inputText.last, !last.isWhitespace {
                inputText.append(" ")
            }
            inputText.append(contentsOf: token)
        }

        selectedSkillDirNames.insert(directoryName)
        dollarTriggerActive = false
        // Intentionally keep `showSkills` open so users can click multiple skills.
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
            out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "$1/\(dir)")
        }
        return out
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.role == .user ? Color.blue.opacity(0.5) : Color.white.opacity(0.08))
                }
                .textSelection(.enabled)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
