import SwiftUI

enum IslandContentType: Equatable {
    case chat
    case settings
}

struct IslandView: View {
    @Bindable var conversationStore: ConversationStore
    var agentBridge: AgentBridge
    var notchSize: CGSize
    @ObservedObject var windowManager: IslandWindowManager

    @State private var contentType: IslandContentType = .chat

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    private var closedWidth: CGFloat { notchSize.width }
    private var closedHeight: CGFloat { notchSize.height }
    private var expandedWidth: CGFloat { 480 }
    private var expandedHeight: CGFloat { 540 }

    private var isExpanded: Bool { windowManager.isExpanded }
    private var isHovering: Bool { windowManager.isHovering }

    private var currentWidth: CGFloat { isExpanded ? expandedWidth : closedWidth }
    private var currentHeight: CGFloat { isExpanded ? expandedHeight : closedHeight }

    private var topRadius: CGFloat { isExpanded ? 19 : 6 }
    private var bottomRadius: CGFloat { isExpanded ? 24 : 14 }

    var body: some View {
        ZStack(alignment: .top) {
            notchContent
                .frame(maxWidth: currentWidth, maxHeight: currentHeight)
                .padding(.horizontal, isExpanded ? topRadius : bottomRadius)
                .padding([.horizontal, .bottom], isExpanded ? 12 : 0)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.black)
                        .frame(height: 1)
                        .padding(.horizontal, topRadius)
                }
                .shadow(
                    color: (isExpanded || isHovering) ? .black.opacity(0.7) : .clear,
                    radius: isExpanded ? 20 : 6,
                    y: isExpanded ? 8 : 2
                )
                .animation(isExpanded ? openAnimation : closeAnimation, value: isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var notchContent: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                openedHeaderContent
                    .frame(height: max(24, closedHeight))

                expandedBody
            }
        } else {
            closedHeaderContent
        }
    }

    // MARK: - Closed Header (inside the notch)

    private var closedHeaderContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.0))

            Text("Flux")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isHovering ? 0.8 : 0.0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }

    // MARK: - Opened Header

    private var openedHeaderContent: some View {
        HStack(spacing: 10) {
            if contentType == .settings {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contentType = .chat
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
                .padding(.leading, 8)

            Text(contentType == .settings ? "Settings" : "Flux")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            if contentType == .chat {
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
                    IslandSettingsView()
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}

// MARK: - In-Island Settings

struct IslandSettingsView: View {
    @AppStorage("anthropicApiKey") private var apiKey = ""
    @AppStorage("discordWebhookUrl") private var discordWebhookUrl = ""
    @AppStorage("slackWebhookUrl") private var slackWebhookUrl = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
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

                divider

                settingsRow(icon: "bubble.left.fill", label: "Discord Webhook", trailing: {
                    AnyView(statusDot(isSet: !discordWebhookUrl.isEmpty))
                })

                settingsRow(icon: "number", label: "Slack Webhook", trailing: {
                    AnyView(statusDot(isSet: !slackWebhookUrl.isEmpty))
                })

                divider

                settingsRow(icon: "eye.fill", label: "Accessibility", trailing: {
                    AnyView(
                        Text(accessibilityEnabled ? "Enabled" : "Enable")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accessibilityEnabled ? .green.opacity(0.8) : .orange.opacity(0.9))
                    )
                })

                settingsRow(icon: "camera.fill", label: "Screen Recording", trailing: {
                    AnyView(
                        Text("Granted")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green.opacity(0.8))
                    )
                })

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
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private var accessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    private func statusDot(isSet: Bool) -> some View {
        Circle()
            .fill(isSet ? Color.green.opacity(0.8) : Color.white.opacity(0.2))
            .frame(width: 8, height: 8)
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
