import SwiftUI

enum AlertLevel {
    case idle
    case warning
    case critical
}

struct WatcherChipPresentation {
    let count: Int
    let cappedText: String
    let level: AlertLevel
}

struct WatcherAlertsChip: View {
    let activeAlerts: [WatcherAlert]
    var onDismissAll: () -> Void
    var onOpenSettings: () -> Void
    var onHide: () -> Void

    @State private var showPopover = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var presentation: WatcherChipPresentation {
        let count = activeAlerts.count
        let level: AlertLevel
        if count >= 10 {
            level = .critical
        } else if count > 0 {
            level = .warning
        } else {
            level = .idle
        }

        let cappedText = count >= 10 ? "9+" : "\(count)"
        return WatcherChipPresentation(count: count, cappedText: cappedText, level: level)
    }

    private var recentAlerts: [WatcherAlert] {
        Array(activeAlerts
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5))
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            StatusChipCapsule(fillOpacity: fillOpacity, strokeOpacity: strokeOpacity) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(iconColor)

                    Text("Alerts")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))

                    Text(presentation.cappedText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(countColor)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(presentation.count) active watcher alert\(presentation.count == 1 ? "" : "s")")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(countColor.opacity(0.9))
                    .frame(width: 8, height: 8)
                Text("\(presentation.count) active watcher alert\(presentation.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if recentAlerts.isEmpty {
                Text("No active alerts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentAlerts) { alert in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(priorityColor(alert.priority))
                                    .frame(width: 6, height: 6)
                                Text(alert.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            Text("\(alert.watcherName) - \(relativeTimestamp(alert.timestamp))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                WatcherPopoverActionButton(title: "Dismiss all", systemImage: "checkmark.circle", role: .normal) {
                    onDismissAll()
                }
                .disabled(recentAlerts.isEmpty)

                WatcherPopoverActionButton(title: "Settings", systemImage: "gearshape", role: .normal) {
                    showPopover = false
                    onOpenSettings()
                }
                WatcherPopoverActionButton(title: "Hide", systemImage: "eye.slash", role: .destructive) {
                    showPopover = false
                    onHide()
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var iconColor: Color {
        switch presentation.level {
        case .idle: return .white.opacity(0.55)
        case .warning: return .orange.opacity(0.9)
        case .critical: return .red.opacity(0.9)
        }
    }

    private var countColor: Color {
        switch presentation.level {
        case .idle: return .white.opacity(0.52)
        case .warning: return .orange.opacity(0.95)
        case .critical: return .red.opacity(0.95)
        }
    }

    private var fillOpacity: Double {
        switch presentation.level {
        case .idle: return StatusChipStyle.defaultFillOpacity
        case .warning: return StatusChipStyle.warningFillOpacity
        case .critical: return StatusChipStyle.criticalFillOpacity
        }
    }

    private var strokeOpacity: Double {
        switch presentation.level {
        case .idle: return StatusChipStyle.defaultStrokeOpacity
        case .warning: return StatusChipStyle.warningStrokeOpacity
        case .critical: return StatusChipStyle.criticalStrokeOpacity
        }
    }

    private func relativeTimestamp(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func priorityColor(_ priority: WatcherAlert.Priority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .info: return .gray
        }
    }
}

private enum WatcherPopoverActionRole {
    case normal
    case destructive
}

private struct WatcherPopoverActionButton: View {
    let title: String
    let systemImage: String
    let role: WatcherPopoverActionRole
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
