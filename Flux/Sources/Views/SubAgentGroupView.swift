import SwiftUI

// MARK: - Sub-Agent Group View

/// Displays sub-agent activity as a colored robot icon with expand/collapse.
/// Each sub-agent gets a deterministic color based on its `agentId`.
struct SubAgentGroupView: View {
    let activity: SubAgentActivity
    @State private var isExpanded = false

    /// Palette of distinct colors for sub-agent icons.
    private static let agentColors: [Color] = [
        Color(hue: 0.55, saturation: 0.7, brightness: 0.9),   // cyan
        Color(hue: 0.78, saturation: 0.6, brightness: 0.85),  // purple
        Color(hue: 0.08, saturation: 0.7, brightness: 0.95),  // orange
        Color(hue: 0.35, saturation: 0.65, brightness: 0.8),  // green
        Color(hue: 0.95, saturation: 0.6, brightness: 0.9),   // pink
        Color(hue: 0.15, saturation: 0.7, brightness: 0.9),   // yellow
        Color(hue: 0.60, saturation: 0.5, brightness: 0.85),  // blue
        Color(hue: 0.45, saturation: 0.6, brightness: 0.8),   // teal
    ]

    private var agentColor: Color {
        let hash = abs(activity.agentId.hashValue)
        return Self.agentColors[hash % Self.agentColors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: robot icon + agent name + spinner
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 14)

                    // Robot icon with agent color
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(agentColor)

                    Text(activity.agentName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    if !activity.toolCalls.isEmpty {
                        Text("(\(activity.toolCalls.count) tool\(activity.toolCalls.count == 1 ? "" : "s"))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    // Status indicator
                    if activity.status == .running {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(agentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(agentColor.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded: show tool calls and result
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    // Sub-agent's internal tool calls
                    ForEach(activity.toolCalls) { call in
                        HStack(spacing: 6) {
                            Group {
                                if call.status == .pending {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.green.opacity(0.7))
                                }
                            }
                            .frame(width: 14)

                            Text(call.toolName
                                .replacingOccurrences(of: "__", with: " → ")
                                .replacingOccurrences(of: "_", with: " ")
                                .capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }

                    // Result preview
                    if let preview = activity.resultPreview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(6)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(agentColor.opacity(0.05))
                            )
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
