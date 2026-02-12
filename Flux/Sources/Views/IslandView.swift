import SwiftUI
import CoreGraphics
import AppKit
@preconcurrency import ApplicationServices

enum IslandContentType: Equatable {
    case chat
    case settings
    case history
    case skills
    case dictationHistory
    case folderDetail(ChatFolder)
    case folderPicker
    case imagePicker
    case tour

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.chat, .chat), (.settings, .settings), (.history, .history), (.skills, .skills), (.folderPicker, .folderPicker), (.imagePicker, .imagePicker): return true
        case (.dictationHistory, .dictationHistory): return true
        case (.tour, .tour): return true
        case (.folderDetail(let a), .folderDetail(let b)): return a.id == b.id
        default: return false
        }
    }
}

struct IslandView: View {
    @Bindable var conversationStore: ConversationStore
    @Bindable var agentBridge: AgentBridge
    var screenCapture: ScreenCapture
    var notchSize: CGSize
    @ObservedObject var windowManager: IslandWindowManager

    @State private var contentType: IslandContentType = .chat
    @State private var showExpandedContent = false
    @State private var measuredChatHeight: CGFloat = 0
    @State private var skillsVisible = false
    @State private var closedIndicatorsLatched = false
    @State private var clearClosedIndicatorsWorkItem: DispatchWorkItem?

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

    private let closedActiveWidthBoost: CGFloat = 72
    private let closedIndicatorLatchDuration: TimeInterval = 1.6

    private var closedIndicatorSlotWidth: CGFloat {
        showClosedActivityIndicators ? (closedActiveWidthBoost / 2) : 0
    }

    private let closedDictationWidthBoost: CGFloat = 80

    private var isDictatingClosed: Bool {
        !isExpanded && DictationManager.shared.isDictating
    }

    private var closedDictationSlotWidth: CGFloat {
        isDictatingClosed ? closedDictationWidthBoost : 0
    }

    private var hasPendingToolCalls: Bool {
        conversationStore.conversations.contains { conversation in
            conversation.messages.contains { message in
                message.toolCalls.contains { $0.status == .pending }
            }
        }
    }

    private var activeConversationAwaitingAssistant: Bool {
        guard let conversation = conversationStore.activeConversation else { return false }
        guard let lastUser = conversation.messages.last(where: { $0.role == .user }) else { return false }
        guard let lastAssistant = conversation.messages.last(where: { $0.role == .assistant }) else { return true }
        return lastUser.timestamp > lastAssistant.timestamp
    }

    private var rawShowClosedActivityIndicators: Bool {
        !isExpanded && (
            agentBridge.isAgentWorking
                || conversationStore.hasRunningConversations
                || hasPendingToolCalls
                || activeConversationAwaitingAssistant
        )
    }

    private var showClosedActivityIndicators: Bool {
        rawShowClosedActivityIndicators || (!isExpanded && closedIndicatorsLatched)
    }

    private var isClosedIndicatorAnimating: Bool {
        !isExpanded && (agentBridge.isAgentWorking || conversationStore.hasRunningConversations)
    }

    private var closedWidth: CGFloat {
        notchSize.width
            + (showClosedActivityIndicators ? closedActiveWidthBoost : 0)
            + (isDictatingClosed ? closedDictationWidthBoost : 0)
    }
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
        if contentType == .settings || contentType == .history || contentType == .skills || contentType == .folderPicker || contentType == .imagePicker || contentType == .dictationHistory || contentType == .tour {
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
                    width: currentWidth + hoverWidthBoost,
                    height: currentHeight + hoverHeightBoost,
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
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: DictationManager.shared.isDictating)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: messageCount)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: contentType)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: measuredChatHeight)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: skillsVisible)
                .padding(.top, hasNotch ? 0 : windowManager.topOffset)

            // Clipboard notification that drops below the island
            if windowManager.showingClipboardNotification {
                ClipboardNotificationView()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .offset(y: currentHeight + hoverHeightBoost + 12 + (hasNotch ? 0 : windowManager.topOffset))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: windowManager.showingClipboardNotification)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                clearClosedIndicatorsWorkItem?.cancel()
                clearClosedIndicatorsWorkItem = nil
                closedIndicatorsLatched = false
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
        .onChange(of: rawShowClosedActivityIndicators) { _, isActive in
            if isActive {
                clearClosedIndicatorsWorkItem?.cancel()
                clearClosedIndicatorsWorkItem = nil
                closedIndicatorsLatched = true
                return
            }

            clearClosedIndicatorsWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                closedIndicatorsLatched = false
                clearClosedIndicatorsWorkItem = nil
            }
            clearClosedIndicatorsWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + closedIndicatorLatchDuration, execute: workItem)
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
        .onReceive(NotificationCenter.default.publisher(for: .islandOpenConversationRequested)) { notification in
            guard let userInfo = notification.userInfo,
                  let conversationIdRaw = userInfo[NotificationPayloadKey.conversationId] as? String,
                  let conversationId = UUID(uuidString: conversationIdRaw) else {
                return
            }
            conversationStore.openConversation(id: conversationId)
            withAnimation(.easeInOut(duration: 0.2)) {
                contentType = .chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandOpenFolderPickerRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                contentType = .folderPicker
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandOpenImagePickerRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                contentType = .imagePicker
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandStartTourRequested)) { _ in
            TourManager.shared.start()
            withAnimation(.easeInOut(duration: 0.2)) {
                contentType = .tour
            }
        }
    }

    @ViewBuilder
    private var notchContent: some View {
        ZStack(alignment: .top) {
            // Closed state — centered in the notch
            closedHeaderContent
                .opacity(isExpanded ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .top)

            // Expanded state — header + body
            VStack(alignment: .leading, spacing: 0) {
                openedHeaderContent
                    .frame(height: max(24, closedHeight))

                expandedBody
            }
            .opacity(showExpandedContent ? 1 : 0)
            .scaleEffect(
                showExpandedContent ? 1 : 0.96,
                anchor: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Closed Header (inside the notch)

    private var closedHeaderContent: some View {
        let showActivity = showClosedActivityIndicators

        return HStack(spacing: 0) {
            ZStack {
                if isDictatingClosed {
                    HStack(spacing: 4) {
                        ClosedWaveformBars(
                            levels: DictationManager.shared.barLevels,
                            isProcessing: DictationManager.shared.isProcessing
                        )
                        ClosedSparklesIndicator(isActive: true)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .frame(width: closedDictationSlotWidth, height: closedHeight, alignment: .leading)

            ZStack {
                if showActivity {
                    ClosedSparklesIndicator(isActive: isClosedIndicatorAnimating)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: closedIndicatorSlotWidth, height: closedHeight)

            Text("Flux")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(showActivity ? 0.92 : (isHovering ? 0.8 : 0.0)))
                .frame(width: notchSize.width, height: closedHeight)

            ZStack {
                if showActivity {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                } else if WakeWordDetector.shared.isEnabled {
                    Circle()
                        .fill(.green.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: closedIndicatorSlotWidth, height: closedHeight)
        }
        .frame(width: closedWidth, height: closedHeight)
        .frame(maxWidth: .infinity, alignment: .top)
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: showActivity)
        .animation(.easeInOut(duration: 0.25), value: isDictatingClosed)
    }

    // MARK: - Opened Header

    private var headerTitle: String {
        switch contentType {
        case .chat: return "Flux"
        case .settings: return "Settings"
        case .history: return "History"
        case .skills: return "Skills"
        case .dictationHistory: return "Dictation"
        case .folderDetail(let folder): return folder.name
        case .folderPicker: return "Workspace"
        case .imagePicker: return "Add Images"
        case .tour: return "Tour"
        }
    }

    private var showBackButton: Bool {
        contentType != .chat && contentType != .tour
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

            if contentType == .chat {
                // Skills Marketplace button (left side, next to title)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .skills
                    }
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                // Dictation History button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .dictationHistory
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

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
                    ChatView(conversationStore: conversationStore, agentBridge: agentBridge, screenCapture: screenCapture)
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
                case .skills:
                    SkillsMarketplaceView()
                case .dictationHistory:
                    DictationHistoryView(historyStore: DictationManager.shared.historyStore)
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
                case .folderPicker:
                    WorkspaceFolderPickerView(
                        conversationStore: conversationStore,
                        onSelect: { url in
                            conversationStore.workspacePath = url.path
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        },
                        onCancel: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        }
                    )
                case .imagePicker:
                    ImageFilePickerView(
                        onSelect: { urls in
                            // Switch back to chat first so ChatView is mounted
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                            // Post on next run loop so ChatView's .onReceive is active
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .islandImageFilesSelected,
                                    object: nil,
                                    userInfo: [NotificationPayloadKey.imageURLs: urls]
                                )
                            }
                        },
                        onCancel: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                contentType = .chat
                            }
                        }
                    )
                case .tour:
                    TourView {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            contentType = .chat
                        }
                    }
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}

private struct ClipboardNotificationView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("Copied to clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.black)
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

private struct ClosedSparklesIndicator: View {
    let isActive: Bool

    @State private var pulse = false
    @State private var twinkle = false

    var body: some View {
        ZStack {
            // Main sparkles icon — gentle breathing pulse with soft glow
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.6))
                .scaleEffect(pulse ? 1.08 : 0.92)
                .offset(y: pulse ? -0.5 : 0.5)
                .rotationEffect(.degrees(pulse ? 4 : -4))
                .shadow(color: .white.opacity(isActive ? 0.7 : 0), radius: isActive ? 6 : 0)
                .shadow(color: .white.opacity(isActive ? 0.3 : 0), radius: isActive ? 12 : 0)

            // Twinkling particle dots at staggered offsets
            SparkDot(isActive: isActive, twinkle: twinkle, offset: CGPoint(x: 7, y: -5), delay: 0)
            SparkDot(isActive: isActive, twinkle: twinkle, offset: CGPoint(x: -5, y: -7), delay: 0.3)
            SparkDot(isActive: isActive, twinkle: twinkle, offset: CGPoint(x: 6, y: 5), delay: 0.6)
        }
        .animation(
            isActive ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
            value: pulse
        )
        .animation(
            isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
            value: twinkle
        )
        .onAppear { setAnimationState(active: isActive) }
        .onChange(of: isActive) { _, active in
            setAnimationState(active: active)
        }
    }

    private func setAnimationState(active: Bool) {
        pulse = active
        twinkle = active
    }
}

private struct SparkDot: View {
    let isActive: Bool
    let twinkle: Bool
    let offset: CGPoint
    let delay: Double

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 2, height: 2)
            .opacity(isActive ? (twinkle ? 0.9 : 0.1) : 0)
            .scaleEffect(twinkle ? 1.2 : 0.4)
            .offset(x: offset.x, y: offset.y)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(delay)
                    : .easeOut(duration: 0.1),
                value: twinkle
            )
    }
}

private struct ClosedWaveformBars: View {
    let levels: [Float]
    let isProcessing: Bool

    private let barCount = 6
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // Use peak level — more responsive than average.
            let peak = levels.max() ?? 0
            // Aggressively amplify so any voice drives full-range animation.
            let energy = min(1.0, Float(peak) * 17)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 1.1
                    let wave = sin(time * 3.0 + phase) * 0.45
                        + sin(time * 5.5 + phase * 1.6) * 0.35
                        + sin(time * 9.0 + phase * 0.7) * 0.2
                    // Wide range [0.05, 1.0] for dramatic ups and downs.
                    let modulation = Float((wave + 1.0) / 2.0 * 0.95 + 0.05)
                    let level = energy * modulation

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white.opacity(0.9))
                        .frame(width: barWidth, height: barHeight(for: level))
                }
            }
            .padding(.leading, 8)
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let maxH: CGFloat = 20
        let minH: CGFloat = 3
        return minH + CGFloat(level) * (maxH - minH)
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
    @AppStorage("dictationAutoCleanFillers") private var dictationAutoCleanFillers = true
    @AppStorage("dictationEnhancementMode") private var dictationEnhancementMode = "none"

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
    @State private var automationService = AutomationService.shared
    @State private var automationsExpanded = false
    @State private var automationEditorMode: InlineAutomationEditorMode?
    @State private var pendingDeleteAutomation: Automation?
    @State private var automationActionError: String?

    // Automation editor fields
    @State private var editorName = ""
    @State private var editorPrompt = ""
    @State private var editorFrequency: ScheduleFrequencyOption = .weekdays
    @State private var editorMinuteInterval = 30
    @State private var editorHour = 9
    @State private var editorMinute = 0
    @State private var editorSelectedDays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var editorDayOfMonth = 1
    @State private var editorTimezone = TimeZone.current.identifier

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

    private enum InlineAutomationEditorMode: Equatable {
        case create
        case edit(String) // automation ID
    }

    private enum ScheduleFrequencyOption: String, CaseIterable, Identifiable {
        case everyMinutes = "Every X min"
        case hourly = "Hourly"
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case monthly = "Monthly"

        var id: String { rawValue }
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

                // Dictation settings
                settingsRow(
                    icon: "waveform",
                    label: "Remove filler words",
                    trailing: {
                        AnyView(
                            Toggle("", isOn: $dictationAutoCleanFillers)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.mini)
                        )
                    }
                )

                settingsRow(
                    icon: "waveform.badge.magnifyingglass",
                    label: "Enhancement mode",
                    trailing: {
                        AnyView(
                            Menu {
                                Button("None") {
                                    dictationEnhancementMode = "none"
                                }
                                Button("Apple Intelligence\(FoundationModelsClient.shared.isAvailable ? "" : " (unavailable)")") {
                                    dictationEnhancementMode = "foundationModels"
                                }
                                Button("Claude") {
                                    dictationEnhancementMode = "claude"
                                }
                            } label: {
                                Text(dictationEnhancementModeDisplayName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .menuStyle(.borderlessButton)
                        )
                    }
                )

                divider

                // Automations header (expandable)
                settingsRow(
                    icon: "clock.badge.checkmark",
                    label: "Automations",
                    trailing: {
                        AnyView(
                            HStack(spacing: 6) {
                                if automationService.activeCount > 0 {
                                    Text("\(automationService.activeCount) active")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green.opacity(0.85))
                                } else {
                                    Text("None")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Image(systemName: automationsExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        )
                    }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        automationsExpanded.toggle()
                    }
                }

                if automationsExpanded {
                    automationsInlineSection
                }

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

                settingsRow(icon: "questionmark.circle", label: "Replay App Tour", trailing: {
                    AnyView(
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    )
                })
                .onTapGesture {
                    NotificationCenter.default.post(name: .islandStartTourRequested, object: nil)
                }

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

    private var automationsInlineSection: some View {
        VStack(spacing: 2) {
            if let automationActionError {
                Text(automationActionError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            let sorted = automationService.automations.sorted { lhs, rhs in
                switch (lhs.nextRunAt, rhs.nextRunAt) {
                case (.some(let a), .some(let b)): return a < b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.createdAt > rhs.createdAt
                }
            }

            ForEach(sorted) { automation in
                automationInlineCard(automation)
            }

            if automationEditorMode != nil {
                automationInlineEditor
            }

            // New automation button
            if automationEditorMode == nil {
                Button {
                    startCreatingAutomation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("New Automation")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog(
            "Delete automation?",
            isPresented: Binding(
                get: { pendingDeleteAutomation != nil },
                set: { if !$0 { pendingDeleteAutomation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pending = pendingDeleteAutomation else { return }
                do {
                    try automationService.deleteAutomation(id: pending.id)
                    automationActionError = nil
                } catch {
                    automationActionError = error.localizedDescription
                }
                pendingDeleteAutomation = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAutomation = nil
            }
        } message: {
            Text(pendingDeleteAutomation?.name ?? "")
        }
    }

    private func automationInlineCard(_ automation: Automation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusDot(isSet: automation.status == .active)

                Text(automation.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 4) {
                Text(SchedulePreset.fromCron(automation.scheduleExpression).displayString)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                if let nextRun = automation.nextRunAt, automation.status == .active {
                    Text("\u{00B7}")
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Next: \(relativeTimeString(nextRun))")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                } else if automation.status == .paused {
                    Text("\u{00B7}")
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Paused")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.7))
                }
            }

            if let summary = automation.lastRunSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Run Now") {
                    do {
                        _ = try automationService.runAutomationNow(id: automation.id)
                        automationActionError = nil
                    } catch {
                        automationActionError = error.localizedDescription
                    }
                }

                if automation.status == .active {
                    Button("Pause") {
                        do {
                            _ = try automationService.pauseAutomation(id: automation.id)
                            automationActionError = nil
                        } catch {
                            automationActionError = error.localizedDescription
                        }
                    }
                } else {
                    Button("Resume") {
                        do {
                            _ = try automationService.resumeAutomation(id: automation.id)
                            automationActionError = nil
                        } catch {
                            automationActionError = error.localizedDescription
                        }
                    }
                }

                Button("Edit") {
                    startEditingAutomation(automation)
                }

                Button("Open Thread") {
                    openAutomationThread(automation)
                }

                Spacer()

                Button("Delete") {
                    pendingDeleteAutomation = automation
                }
                .foregroundStyle(.red.opacity(0.7))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var automationInlineEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(automationEditorMode == .create ? "New Automation" : "Edit Automation")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Automation name", text: $editorName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                    .onAppear {
                        IslandWindowManager.shared.makeKeyIfNeeded()
                    }
            }

            // Schedule frequency
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 8) {
                    Menu {
                        ForEach(ScheduleFrequencyOption.allCases) { option in
                            Button(option.rawValue) {
                                editorFrequency = option
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(editorFrequency.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                    }
                    .menuStyle(.borderlessButton)

                    scheduleSubFields
                }
            }

            // Weekday selector (only for weekly)
            if editorFrequency == .weekly {
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases) { day in
                        Button {
                            if editorSelectedDays.contains(day) {
                                editorSelectedDays.remove(day)
                            } else {
                                editorSelectedDays.insert(day)
                            }
                        } label: {
                            Text(day.shortAbbreviation)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(editorSelectedDays.contains(day) ? Color.green.opacity(0.3) : Color.white.opacity(0.06))
                                )
                                .foregroundStyle(editorSelectedDays.contains(day) ? .green.opacity(0.9) : .white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Prompt
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                TextEditor(text: $editorPrompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .onAppear {
                        IslandWindowManager.shared.makeKeyIfNeeded()
                    }
            }

            // Save/Cancel
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    automationEditorMode = nil
                    automationActionError = nil
                }
                .foregroundStyle(.white.opacity(0.5))

                Button("Save") {
                    saveAutomation()
                }
                .foregroundStyle(.green.opacity(0.9))
                .disabled(editorPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var scheduleSubFields: some View {
        switch editorFrequency {
        case .everyMinutes:
            Menu {
                ForEach([5, 10, 15, 30], id: \.self) { n in
                    Button("\(n) min") {
                        editorMinuteInterval = n
                    }
                }
            } label: {
                Text("\(editorMinuteInterval) min")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)

        case .hourly:
            EmptyView()

        case .daily, .weekdays, .weekly:
            timePickers

        case .monthly:
            HStack(spacing: 6) {
                Menu {
                    ForEach(1...31, id: \.self) { d in
                        Button("Day \(d)") {
                            editorDayOfMonth = d
                        }
                    }
                } label: {
                    Text("Day \(editorDayOfMonth)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)

                timePickers
            }

        }
    }

    private var timePickers: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(0..<24, id: \.self) { h in
                    Button(String(format: "%d %@", h == 0 ? 12 : (h > 12 ? h - 12 : h), h >= 12 ? "PM" : "AM")) {
                        editorHour = h
                    }
                }
            } label: {
                Text(String(format: "%d %@", editorHour == 0 ? 12 : (editorHour > 12 ? editorHour - 12 : editorHour), editorHour >= 12 ? "PM" : "AM"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)

            Text(":")
                .foregroundStyle(.white.opacity(0.3))

            Menu {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Button(String(format: ":%02d", m)) {
                        editorMinute = m
                    }
                }
            } label: {
                Text(String(format: ":%02d", editorMinute))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func startCreatingAutomation() {
        editorName = ""
        editorPrompt = ""
        editorFrequency = .weekdays
        editorHour = 9
        editorMinute = 0
        editorMinuteInterval = 30
        editorSelectedDays = [.monday, .wednesday, .friday]
        editorDayOfMonth = 1
        editorTimezone = TimeZone.current.identifier
        automationEditorMode = .create
        automationActionError = nil
    }

    private func startEditingAutomation(_ automation: Automation) {
        editorName = automation.name
        editorPrompt = automation.prompt
        editorTimezone = automation.timezoneIdentifier

        let preset = SchedulePreset.fromCron(automation.scheduleExpression)
        switch preset {
        case .everyMinutes(let n):
            editorFrequency = .everyMinutes
            editorMinuteInterval = n
        case .hourly:
            editorFrequency = .hourly
        case .daily(let h, let m):
            editorFrequency = .daily
            editorHour = h
            editorMinute = m
        case .weekdays(let h, let m):
            editorFrequency = .weekdays
            editorHour = h
            editorMinute = m
        case .weekly(let days, let h, let m):
            editorFrequency = .weekly
            editorSelectedDays = days
            editorHour = h
            editorMinute = m
        case .monthly(let d, let h, let m):
            editorFrequency = .monthly
            editorDayOfMonth = d
            editorHour = h
            editorMinute = m
        case .custom:
            editorFrequency = .weekly
            editorSelectedDays = Set(Weekday.allCases)
            editorHour = 9
            editorMinute = 0
        }

        automationEditorMode = .edit(automation.id)
        automationActionError = nil
    }

    private func buildPresetFromEditor() -> SchedulePreset {
        switch editorFrequency {
        case .everyMinutes:
            return .everyMinutes(editorMinuteInterval)
        case .hourly:
            return .hourly
        case .daily:
            return .daily(hour: editorHour, minute: editorMinute)
        case .weekdays:
            return .weekdays(hour: editorHour, minute: editorMinute)
        case .weekly:
            return .weekly(days: editorSelectedDays.isEmpty ? [.monday] : editorSelectedDays, hour: editorHour, minute: editorMinute)
        case .monthly:
            return .monthly(day: editorDayOfMonth, hour: editorHour, minute: editorMinute)
        }
    }

    private func saveAutomation() {
        let cronExpr = buildPresetFromEditor().toCron()
        let trimmedName = editorName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch automationEditorMode {
            case .create:
                _ = try automationService.createAutomation(
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    prompt: editorPrompt,
                    scheduleExpression: cronExpr,
                    timezoneIdentifier: editorTimezone
                )
            case .edit(let id):
                _ = try automationService.updateAutomation(
                    id: id,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    prompt: editorPrompt,
                    scheduleExpression: cronExpr,
                    timezoneIdentifier: editorTimezone
                )
            case nil:
                break
            }
            automationEditorMode = nil
            automationActionError = nil
        } catch {
            automationActionError = error.localizedDescription
        }
    }

    private func openAutomationThread(_ automation: Automation) {
        guard let conversationId = UUID(uuidString: automation.conversationId) else {
            automationActionError = "Automation thread ID is invalid."
            return
        }
        automationActionError = nil

        NotificationCenter.default.post(
            name: .automationOpenThreadRequested,
            object: nil,
            userInfo: [
                NotificationPayloadKey.conversationId: conversationId.uuidString,
                NotificationPayloadKey.conversationTitle: "Automation: \(automation.name)",
            ]
        )
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

        SkillPermission.accessibility.openSystemSettings()
    }

    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        SkillPermission.screenRecording.openSystemSettings()
    }

    private func relaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    private func statusDot(isSet: Bool) -> some View {
        Circle()
            .fill(isSet ? Color.green.opacity(0.8) : Color.white.opacity(0.2))
            .frame(width: 8, height: 8)
    }

    private var dictationEnhancementModeDisplayName: String {
        switch dictationEnhancementMode {
        case "foundationModels": return "Apple Intelligence"
        case "claude": return "Claude"
        default: return "None"
        }
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
