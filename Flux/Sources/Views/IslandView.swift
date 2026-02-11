import SwiftUI
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices

enum IslandContentType: Equatable {
    case chat
    case settings
    case history
    case folderDetail(ChatFolder)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chat, .chat), (.settings, .settings), (.history, .history): return true
        case (.folderDetail(let a), .folderDetail(let b)): return a.id == b.id
        default: return false
        }
    }
}

struct IslandView: View {
    @Bindable var conversationStore: ConversationStore
    var agentBridge: AgentBridge
    var notchSize: CGSize
    @ObservedObject var windowManager: IslandWindowManager

    @State private var contentType: IslandContentType = .chat
    @State private var showExpandedContent = false
    @State private var measuredChatHeight: CGFloat = 0
    @State private var skillsVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Shell shape animation: slow, bouncy spring — feels alive, like a liquid blob
    private var openAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 1.1, dampingFraction: 0.68, blendDuration: 0)
    }

    // Close retracts fluidly back into the notch
    private var closeAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0)
    }

    private var closedWidth: CGFloat { notchSize.width }
    private var closedHeight: CGFloat { notchSize.height }
    private var expandedWidth: CGFloat { 480 }
    private let maxExpandedHeight: CGFloat = 540
    private let minExpandedHeight: CGFloat = 100

    private var isExpanded: Bool { windowManager.isExpanded }
    private var isHovering: Bool { windowManager.isHovering }
    private var hasNotch: Bool { windowManager.hasNotch }

    private var messageCount: Int {
        conversationStore.activeConversation?.messages.count ?? 0
    }

    private var expandedHeight: CGFloat {
        if contentType == .settings || contentType == .history {
            return maxExpandedHeight
        }
        if case .folderDetail = contentType {
            return maxExpandedHeight
        }
        // No messages yet — compact initial state with just the input row
        if messageCount == 0 && !skillsVisible {
            return minExpandedHeight + 80
        }
        // Grow to fit measured chat content + header + input row + padding
        // Header ~36pt, input row ~52pt, divider + padding ~20pt
        let overhead: CGFloat = 108
        let desired = measuredChatHeight + overhead
        // When skills are visible the list is in the VStack flow, so measuredChatHeight
        // already includes it. Allow a larger cap so the full list can display.
        let cap: CGFloat = skillsVisible ? 700 : maxExpandedHeight
        return min(max(desired, minExpandedHeight + 80), cap)
    }

    private var currentWidth: CGFloat { isExpanded ? expandedWidth : closedWidth }
    private var currentHeight: CGFloat { isExpanded ? expandedHeight : closedHeight }

    private var topRadius: CGFloat { isExpanded ? 19 : 6 }
    private var bottomRadius: CGFloat { isExpanded ? 24 : 14 }
    /// Corner radius used for the pill shape on non-notch screens.
    private var pillRadius: CGFloat { isExpanded ? 24 : closedHeight / 2 }

    // Hover "breathe" — subtle width bump to hint interactivity
    private var hoverWidthBoost: CGFloat { (!isExpanded && isHovering) ? 8 : 0 }
    private var hoverHeightBoost: CGFloat { (!isExpanded && isHovering) ? 2 : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            notchContent
                .frame(
                    maxWidth: currentWidth + hoverWidthBoost,
                    maxHeight: currentHeight + hoverHeightBoost,
                    alignment: .top
                )
                .padding(.horizontal, isExpanded ? topRadius : bottomRadius)
                .padding([.horizontal, .bottom], isExpanded ? 12 : 0)
                .background(.black)
                .clipShape(
                    hasNotch
                        ? AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
                        : AnyShape(RoundedRectangle(cornerRadius: pillRadius, style: .continuous))
                )
                .overlay(alignment: .top) {
                    if hasNotch {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topRadius)
                    }
                }
                .overlay {
                    if !hasNotch {
                        RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
                }
                .shadow(
                    color: (isExpanded || isHovering) ? .black.opacity(0.7) : .clear,
                    radius: isExpanded ? 20 : 6,
                    y: isExpanded ? 8 : 2
                )
                .animation(isExpanded ? openAnimation : closeAnimation, value: isExpanded)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isHovering)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: messageCount)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: contentType)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: measuredChatHeight)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: skillsVisible)
                .padding(.top, hasNotch ? 0 : windowManager.topOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                windowManager.expandedContentSize = CGSize(width: expandedWidth, height: expandedHeight)
                // Content fades in after the shell has finished its bounce
                withAnimation(
                    reduceMotion
                        ? .easeIn(duration: 0.1)
                        : .smooth(duration: 0.5).delay(0.3)
                ) {
                    showExpandedContent = true
                }
            } else {
                // Content vanishes quickly, then the shell retracts
                showExpandedContent = false
            }
        }
        .onChange(of: messageCount) { _, _ in
            if isExpanded {
                windowManager.expandedContentSize = CGSize(width: expandedWidth, height: expandedHeight)
            }
        }
        .onChange(of: contentType) { _, _ in
            if isExpanded {
                windowManager.expandedContentSize = CGSize(width: expandedWidth, height: expandedHeight)
            }
        }
        .onPreferenceChange(ChatContentHeightKey.self) { height in
            measuredChatHeight = height
        }
        .onPreferenceChange(SkillsVisibleKey.self) { visible in
            skillsVisible = visible
        }
        .onChange(of: measuredChatHeight) { _, _ in
            if isExpanded {
                windowManager.expandedContentSize = CGSize(width: expandedWidth, height: expandedHeight)
            }
        }
        .onChange(of: skillsVisible) { _, _ in
            if isExpanded {
                windowManager.expandedContentSize = CGSize(width: expandedWidth, height: expandedHeight)
            }
        }
    }

    @ViewBuilder
    private var notchContent: some View {
        ZStack {
            // Closed state — centered in the notch
            closedHeaderContent
                .opacity(isExpanded ? 0 : 1)

            // Expanded state — header + body
            VStack(alignment: .leading, spacing: 0) {
                openedHeaderContent
                    .frame(height: max(24, closedHeight))

                expandedBody
                    .opacity(showExpandedContent ? 1 : 0)
                    .scaleEffect(
                        showExpandedContent ? 1 : 0.96,
                        anchor: .top
                    )
            }
            .opacity(isExpanded ? 1 : 0)
        }
    }

    // MARK: - Closed Header (inside the notch)

    private var closedHeaderContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.9 : (hasNotch ? 0.0 : 0.3)))

            Text("Flux")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isHovering ? 0.8 : (hasNotch ? 0.0 : 0.25)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }

    // MARK: - Opened Header

    private var headerTitle: String {
        switch contentType {
        case .chat: return "Flux"
        case .settings: return "Settings"
        case .history: return "History"
        case .folderDetail(let folder): return folder.name
        }
    }

    private var showBackButton: Bool {
        contentType != .chat
    }

    private var backDestination: IslandContentType {
        switch contentType {
        case .folderDetail: return .history
        default: return .chat
        }
    }

    private var openedHeaderContent: some View {
        HStack(spacing: 10) {
            if showBackButton {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = backDestination
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, showBackButton ? 0 : 8)

            Text(headerTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if contentType == .chat {
                // New Chat button
                Button {
                    conversationStore.startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                // History button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .history
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                // Settings button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .settings
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            if contentType == .history {
                // New Chat button in history header
                Button {
                    conversationStore.startNewConversation()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .chat
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            Button {
                windowManager.collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Expanded Body (below header)

    private var expandedBody: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.1))

            Group {
                switch contentType {
                case .chat:
                    ChatView(conversationStore: conversationStore, agentBridge: agentBridge)
                case .settings:
                    IslandSettingsView(agentBridge: agentBridge)
                case .history:
                    ChatHistoryView(
                        conversationStore: conversationStore,
                        onOpenChat: { id in
                            conversationStore.openConversation(id: id)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        },
                        onNewChat: {
                            conversationStore.startNewConversation()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        },
                        onOpenFolder: { folder in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .folderDetail(folder)
                            }
                        }
                    )
                case .folderDetail(let folder):
                    FolderDetailView(
                        conversationStore: conversationStore,
                        folder: folder,
                        onOpenChat: { id in
                            conversationStore.openConversation(id: id)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        }
                    )
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}

// MARK: - In-Island Settings

struct IslandSettingsView: View {
    var agentBridge: AgentBridge

    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordChannelId") private var discordChannelId = ""
    @AppStorage("slackChannelId") private var slackChannelId = ""
    @AppStorage("telegramChatId") private var telegramChatId = ""
    @AppStorage("linearMcpToken") private var linearMcpToken = ""
    @AppStorage("chatTitleCreator") private var chatTitleCreatorRaw = ChatTitleCreator.foundationModels.rawValue

    @State private var discordBotToken = ""
    @State private var slackBotToken = ""
    @State private var telegramBotToken = ""
    @State private var secretsLoaded = false
    @State private var editingField: EditingField?
    @FocusState private var fieldFocused: Bool
    @State private var permissionRefreshToken: Int = 0
    @State private var telegramPairingCode = ""
    @State private var telegramPending: [TelegramPairingRequest] = []
    @State private var telegramPairingError: String?

    private enum EditingField: Hashable {
        case apiKey
        case linearToken
        case discordBotToken
        case discordChannelId
        case slackBotToken
        case slackChannelId
        case telegramBotToken
        case telegramChatId
        case telegramPairingCode
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                // API Key
                if editingField == .apiKey {
                    editableRow(icon: "key.fill", label: "API Key") {
                        SecureField("sk-ant-...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit { editingField = nil }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        editingField = nil
                    }
                } else {
                    settingsRow(
                        icon: "key.fill",
                        label: "API Key",
                        trailing: {
                            AnyView(
                                Text(apiKey.isEmpty ? "Not set" : "••••\(apiKey.suffix(4))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(apiKey.isEmpty ? .red.opacity(0.8) : .green.opacity(0.8))
                            )
                        }
                    )
                    .onTapGesture {
                        editingField = .apiKey
                    }
                }

                divider

                settingsRow(
                    icon: "text.quote",
                    label: "Chat Title Creator",
                    trailing: {
                        AnyView(
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(ChatTitleCreator.allCases) { creator in
                                        Button(creator.displayName) {
                                            chatTitleCreatorRaw = creator.rawValue
                                        }
                                    }
                                } label: {
                                    Text((ChatTitleCreator(rawValue: chatTitleCreatorRaw) ?? .foundationModels).displayName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .menuStyle(.borderlessButton)

                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .help("Controls how Flux generates titles for new chats.")
                            }
                        )
                    }
                )

                divider

                // Linear MCP Token
                if editingField == .linearToken {
                    editableRow(icon: "rectangle.connected.to.line.below", label: "Linear MCP Token") {
                        SecureField("...", text: $linearMcpToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit { editingField = nil }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        editingField = nil
                    }
                } else {
                    settingsRow(
                        icon: "rectangle.connected.to.line.below",
                        label: "Linear MCP Token",
                        trailing: {
                            AnyView(
                                Text(linearMcpToken.isEmpty ? "Not set" : "••••\(linearMcpToken.suffix(4))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(linearMcpToken.isEmpty ? .red.opacity(0.8) : .green.opacity(0.8))
                            )
                        }
                    )
                    .onTapGesture {
                        editingField = .linearToken
                    }
                }

                divider

                // Discord Bot
                if editingField == .discordBotToken {
                    editableRow(icon: "bubble.left.fill", label: "Discord Bot Token") {
                        SecureField("Bot token", text: $discordBotToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit {
                                persistDiscordBotToken()
                                editingField = nil
                            }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        persistDiscordBotToken()
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "bubble.left.fill", label: "Discord Bot", trailing: {
                        AnyView(
                            HStack(spacing: 8) {
                                statusDot(isSet: !discordBotToken.isEmpty && !discordChannelId.isEmpty)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .help(discordBotHelp)
                            }
                        )
                    })
                    .onTapGesture {
                        editingField = .discordBotToken
                    }
                }

                if editingField == .discordChannelId {
                    editableRow(icon: "bubble.left.fill", label: "Discord Channel ID") {
                        TextField("Channel ID (e.g. 123456789012345678)", text: $discordChannelId)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit { editingField = nil }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "bubble.left.fill", label: "Discord Channel ID", trailing: {
                        AnyView(statusDot(isSet: !discordChannelId.isEmpty))
                    })
                    .onTapGesture {
                        editingField = .discordChannelId
                    }
                }

                // Slack Bot
                if editingField == .slackBotToken {
                    editableRow(icon: "number", label: "Slack Bot Token") {
                        SecureField("xoxb-...", text: $slackBotToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit {
                                persistSlackBotToken()
                                editingField = nil
                            }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        persistSlackBotToken()
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "number", label: "Slack Bot", trailing: {
                        AnyView(
                            HStack(spacing: 8) {
                                statusDot(isSet: !slackBotToken.isEmpty && !slackChannelId.isEmpty)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .help(slackBotHelp)
                            }
                        )
                    })
                    .onTapGesture {
                        editingField = .slackBotToken
                    }
                }

                if editingField == .slackChannelId {
                    editableRow(icon: "number", label: "Slack Channel ID") {
                        TextField("Channel ID (e.g. C123...)", text: $slackChannelId)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit { editingField = nil }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "number", label: "Slack Channel ID", trailing: {
                        AnyView(statusDot(isSet: !slackChannelId.isEmpty))
                    })
                    .onTapGesture {
                        editingField = .slackChannelId
                    }
                }

                // Telegram Bot
                if editingField == .telegramBotToken {
                    editableRow(icon: "paperplane.fill", label: "Telegram Bot Token") {
                        SecureField("Bot token", text: $telegramBotToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit {
                                persistTelegramBotToken()
                                editingField = nil
                            }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        persistTelegramBotToken()
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "paperplane.fill", label: "Telegram Bot", trailing: {
                        AnyView(
                            HStack(spacing: 8) {
                                statusDot(isSet: !telegramBotToken.isEmpty && !telegramChatId.isEmpty)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .help(telegramBotHelp)
                            }
                        )
                    })
                    .onTapGesture {
                        editingField = .telegramBotToken
                    }
                }

                if editingField == .telegramChatId {
                    editableRow(icon: "paperplane.fill", label: "Telegram Chat ID") {
                        TextField("Chat ID (e.g. 123456789)", text: $telegramChatId)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit {
                                notifyTelegramConfigChanged()
                                editingField = nil
                            }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        notifyTelegramConfigChanged()
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "paperplane.fill", label: "Telegram Chat ID", trailing: {
                        AnyView(statusDot(isSet: !telegramChatId.isEmpty))
                    })
                    .onTapGesture {
                        editingField = .telegramChatId
                    }
                }

                if editingField == .telegramPairingCode {
                    editableRow(icon: "paperplane.fill", label: "Telegram Pairing Code") {
                        TextField("PAIRCODE", text: $telegramPairingCode)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .onSubmit {
                                approveTelegramPairing()
                                editingField = nil
                            }
                            .onAppear {
                                IslandWindowManager.shared.makeKeyIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    fieldFocused = true
                                }
                            }
                    } onDone: {
                        approveTelegramPairing()
                        editingField = nil
                    }
                } else {
                    settingsRow(icon: "paperplane.fill", label: "Telegram Pairing", trailing: {
                        AnyView(
                            Text(telegramPending.isEmpty ? "None" : "\(telegramPending.count) pending")
                                .font(.system(size: 12))
                                .foregroundStyle(telegramPending.isEmpty ? .white.opacity(0.5) : .orange.opacity(0.9))
                        )
                    })
                    .onTapGesture {
                        editingField = .telegramPairingCode
                    }
                }

                if !telegramPending.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(telegramPending) { request in
                            HStack(spacing: 8) {
                                Text(request.username.map { "@\($0)" } ?? "Chat \(request.chatId)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Button {
                                    TelegramPairingStore.removePending(chatId: request.chatId)
                                    loadTelegramPairing()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                }

                if let telegramPairingError {
                    Text(telegramPairingError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                }

                divider

                settingsRow(icon: "eye.fill", label: "Accessibility", trailing: {
                    AnyView(
                        Text(accessibilityEnabled ? "Enabled" : "Enable")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accessibilityEnabled ? .green.opacity(0.8) : .orange.opacity(0.9))
                    )
                })
                .onTapGesture {
                    requestAccessibilityPermission()
                }

                settingsRow(icon: "camera.fill", label: "Screen Recording", trailing: {
                    AnyView(
                        Text(screenRecordingGranted ? "Granted" : "Enable")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(screenRecordingGranted ? .green.opacity(0.8) : .orange.opacity(0.9))
                    )
                })
                .onTapGesture {
                    requestScreenRecordingPermission()
                }

                if !accessibilityEnabled || !screenRecordingGranted {
                    settingsRow(icon: "arrow.clockwise", label: "Restart Flux", trailing: {
                        AnyView(EmptyView())
                    })
                    .onTapGesture {
                        relaunch()
                    }
                }

                divider

                settingsRow(icon: "arrow.triangle.2.circlepath", label: "Launch at Login", trailing: {
                    AnyView(EmptyView())
                })

                divider

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "power")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 16)

                        Text("Quit Flux")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.clear))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadSecretsIfNeeded()
        }
        .onChange(of: editingField) { old, _ in
            switch old {
            case .apiKey:
                agentBridge.sendApiKey(apiKey)
            case .discordBotToken:
                persistDiscordBotToken()
            case .slackBotToken:
                persistSlackBotToken()
            case .telegramBotToken:
                persistTelegramBotToken()
            case .telegramChatId:
                notifyTelegramConfigChanged()
            case .telegramPairingCode:
                approveTelegramPairing()
            default:
                break
            }
        }
        .task {
            // Poll while Settings is visible so status updates after the user toggles permissions in System Settings.
            while !Task.isCancelled {
                permissionRefreshToken &+= 1
                loadTelegramPairing()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private var accessibilityEnabled: Bool {
        _ = permissionRefreshToken
        return AXIsProcessTrusted()
    }

    private var screenRecordingGranted: Bool {
        _ = permissionRefreshToken
        return CGPreflightScreenCaptureAccess()
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // The "prompt" typically opens System Settings rather than showing a modal prompt.
        openSystemSettingsPrivacyPane(type: .accessibility)
    }

    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        openSystemSettingsPrivacyPane(type: .screenRecording)
    }

    private enum PrivacyPaneType {
        case accessibility
        case screenRecording
    }

    private func openSystemSettingsPrivacyPane(type: PrivacyPaneType) {
        let candidates: [String]
        switch type {
        case .accessibility:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .screenRecording:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }

        for str in candidates {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }

        // Fallback: open System Settings if deep-links aren't supported.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func relaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            NSApp.terminate(nil)
        }
    }

    private func statusDot(isSet: Bool) -> some View {
        Circle()
            .fill(isSet ? Color.green.opacity(0.8) : Color.white.opacity(0.2))
            .frame(width: 8, height: 8)
    }

    private var discordBotHelp: String {
        [
            "Discord bot setup:",
            "1) Create a bot at Discord Developer Portal (Applications -> Bot).",
            "2) Copy the bot token and paste it into \"Discord Bot\".",
            "3) Invite the bot to your server with \"Send Messages\" permission.",
            "4) Enable Developer Mode in Discord, then right click a channel -> Copy Channel ID.",
        ].joined(separator: "\n")
    }

    private var slackBotHelp: String {
        [
            "Slack bot setup:",
            "1) Create a Slack app (From scratch) with a Bot user.",
            "2) Under OAuth & Permissions, add scopes: chat:write (+ chat:write.public for public channels without inviting the bot).",
            "3) Install the app to your workspace and copy the Bot User OAuth Token (xoxb-...).",
            "4) Copy the channel ID (starts with C or G). Invite the bot for private channels.",
        ].joined(separator: "\n")
    }

    private var telegramBotHelp: String {
        [
            "Telegram bot setup:",
            "1) Create a bot with @BotFather and copy the token.",
            "2) Paste the token into \"Telegram Bot\".",
            "3) DM the bot to receive a pairing code.",
            "4) Paste the pairing code into \"Telegram Pairing Code\" to approve.",
            "5) For groups, mention @YourBotName to trigger responses.",
        ].joined(separator: "\n")
    }

    private func loadSecretsIfNeeded() {
        guard !secretsLoaded else { return }
        secretsLoaded = true

        discordBotToken = KeychainService.getString(forKey: SecretKeys.discordBotToken) ?? ""
        slackBotToken = KeychainService.getString(forKey: SecretKeys.slackBotToken) ?? ""
        telegramBotToken = KeychainService.getString(forKey: SecretKeys.telegramBotToken) ?? ""
    }

    private func persistDiscordBotToken() {
        do {
            try KeychainService.setString(discordBotToken, forKey: SecretKeys.discordBotToken)
        } catch {
            // Best effort; ignore.
        }
    }

    private func persistSlackBotToken() {
        do {
            try KeychainService.setString(slackBotToken, forKey: SecretKeys.slackBotToken)
        } catch {
            // Best effort; ignore.
        }
    }

    private func persistTelegramBotToken() {
        do {
            try KeychainService.setString(telegramBotToken, forKey: SecretKeys.telegramBotToken)
        } catch {
            // Best effort; ignore.
        }
        notifyTelegramConfigChanged()
    }

    private func notifyTelegramConfigChanged() {
        NotificationCenter.default.post(name: .telegramConfigDidChange, object: nil)
    }

    private func loadTelegramPairing() {
        telegramPending = TelegramPairingStore.loadPending()
    }

    private func approveTelegramPairing() {
        telegramPairingError = nil
        let code = telegramPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let _ = TelegramPairingStore.approve(code: code) else {
            if !code.isEmpty {
                telegramPairingError = "Pairing code not found or expired."
            }
            return
        }
        telegramPairingCode = ""
        loadTelegramPairing()
    }

    private func editableRow<Field: View>(
        icon: String,
        label: String,
        @ViewBuilder field: () -> Field,
        onDone: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                field()
            }

            Button {
                onDone()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private func settingsRow(
        icon: String,
        label: String,
        trailing: () -> AnyView
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.0001)))
    }
}
