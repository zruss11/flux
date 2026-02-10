import SwiftUI

struct ChatView: View {
    @Bindable var conversationStore: ConversationStore
    var agentBridge: AgentBridge
    @State private var inputText = ""
    @State private var voiceInput = VoiceInput()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
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

                TextField("Message Flux...", text: $inputText)
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

        var conversationId: UUID
        if let activeId = conversationStore.activeConversationId {
            conversationId = activeId
        } else {
            let conversation = conversationStore.createConversation()
            conversationId = conversation.id
        }

        conversationStore.addMessage(to: conversationId, role: .user, content: text)
        agentBridge.sendChatMessage(conversationId: conversationId.uuidString, content: text)

        inputText = ""
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
