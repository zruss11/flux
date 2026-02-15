import SwiftUI

enum CIChipVisualState: Equatable {
    case passing
    case failing
    case running
    case unknown

    init?(_ status: CIAggregateStatus) {
        switch status {
        case .passing:
            self = .passing
        case .failing:
            self = .failing
        case .running:
            self = .running
        case .unknown:
            self = .unknown
        case .idle:
            return nil
        }
    }

    var iconName: String {
        switch self {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.octagon.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .passing: return .green
        case .failing: return .red
        case .running: return .orange
        case .unknown: return .white
        }
    }

    var statusText: String {
        switch self {
        case .passing: return "All checks passing"
        case .failing: return "Failing checks detected"
        case .running: return "Checks currently running"
        case .unknown: return "Status unavailable"
        }
    }
}

struct CIStatusChip: View {
    let aggregateStatus: CIAggregateStatus
    let repoStatuses: [String: CIAggregateStatus]
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPopover = false
    @State private var runIconSpinning = false

    private var visualState: CIChipVisualState? {
        CIChipVisualState(aggregateStatus)
    }

    private var sortedStatuses: [(repo: String, status: CIAggregateStatus)] {
        repoStatuses
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending }
    }

    private var chipDetailLabel: String? {
        let count = sortedStatuses.count
        if count > 1 {
            return "\(count)"
        }
        if let first = sortedStatuses.first {
            return shortRepoName(first.repo)
        }
        return nil
    }

    var body: some View {
        if let visualState {
            Button {
                showPopover.toggle()
            } label: {
                StatusChipCapsule(fillOpacity: StatusChipStyle.defaultFillOpacity, strokeOpacity: StatusChipStyle.defaultStrokeOpacity) {
                    HStack(spacing: 4) {
                        Image(systemName: visualState.iconName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(visualState.tint.opacity(0.9))
                            .rotationEffect(
                                visualState == .running && !reduceMotion && runIconSpinning
                                    ? .degrees(360)
                                    : .degrees(0)
                            )
                            .animation(
                                visualState == .running && !reduceMotion && runIconSpinning
                                    ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: runIconSpinning
                            )

                        Text("CI")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))

                        if let chipDetailLabel {
                            Text(chipDetailLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .help(visualState.statusText)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverContent(visualState: visualState)
            }
            .onAppear {
                updateRunSpinState(visualState: visualState)
            }
            .onChange(of: visualState) { _, newState in
                updateRunSpinState(visualState: newState)
            }
        }
    }

    @ViewBuilder
    private func popoverContent(visualState: CIChipVisualState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(visualState.tint.opacity(0.9))
                    .frame(width: 8, height: 8)
                Text(visualState.statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if sortedStatuses.isEmpty {
                Text("No watched repositories configured.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sortedStatuses, id: \.repo) { entry in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: entry.status))
                                .frame(width: 6, height: 6)
                            Text(entry.repo)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(label(for: entry.status))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                StatusPopoverActionButton(title: "Refresh", systemImage: "arrow.clockwise", role: .normal) {
                    onRefresh()
                }
                StatusPopoverActionButton(title: "Repos", systemImage: "gearshape", role: .normal) {
                    showPopover = false
                    onOpenSettings()
                }
                StatusPopoverActionButton(title: "Hide", systemImage: "eye.slash", role: .destructive) {
                    showPopover = false
                    onHide()
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func updateRunSpinState(visualState: CIChipVisualState?) {
        runIconSpinning = visualState == .running && !reduceMotion
    }

    private func shortRepoName(_ repo: String) -> String {
        let suffix = repo.split(separator: "/").last.map(String.init) ?? repo
        if suffix.count <= 8 {
            return suffix
        }
        return String(suffix.prefix(7)) + "..."
    }

    private func color(for status: CIAggregateStatus) -> Color {
        switch status {
        case .passing: return .green
        case .failing: return .red
        case .running: return .orange
        case .unknown: return .gray
        case .idle: return .gray.opacity(0.4)
        }
    }

    private func label(for status: CIAggregateStatus) -> String {
        switch status {
        case .passing: return "Passing"
        case .failing: return "Failing"
        case .running: return "Running"
        case .unknown: return "Unknown"
        case .idle: return "Idle"
        }
    }
}

private enum StatusPopoverActionRole {
    case normal
    case destructive
}

private struct StatusPopoverActionButton: View {
    let title: String
    let systemImage: String
    let role: StatusPopoverActionRole
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
