import SwiftUI

// MARK: - Glance Item Model

/// Represents a single card in the At a Glance section.
/// Priority determines sort order (lower = more urgent = shown first).
enum GlanceItem: Identifiable, Sendable {
    case ciFailing(repos: [String])
    case watcherAlert(title: String, summary: String, type: String, timestamp: Date, totalCount: Int)
    case ciRunning(repos: [String])
    case clipboard(content: String, timestamp: Date)
    case recentActivity(appName: String, windowTitle: String?, startedAt: Date)
    case ciPassing(repoCount: Int)
    case gitBranch(branch: String)

    var id: String {
        switch self {
        case .ciFailing:       return "ci-failing"
        case .watcherAlert:    return "watcher-alert"
        case .ciRunning:       return "ci-running"
        case .clipboard:       return "clipboard"
        case .recentActivity:  return "recent-activity"
        case .ciPassing:       return "ci-passing"
        case .gitBranch:       return "git-branch"
        }
    }

    /// Lower = higher urgency = shown first.
    var sortPriority: Int {
        switch self {
        case .ciFailing:       return 0
        case .watcherAlert:    return 1
        case .ciRunning:       return 2
        case .clipboard:       return 3
        case .recentActivity:  return 4
        case .gitBranch:       return 5
        case .ciPassing:       return 6
        }
    }

    var icon: String {
        switch self {
        case .ciFailing:                            return "xmark.circle.fill"
        case .watcherAlert(_, _, let type, _, _):   return watcherIconName(type)
        case .ciRunning:                            return "arrow.triangle.2.circlepath"
        case .clipboard:                            return "doc.on.clipboard"
        case .recentActivity(let app, _, _):        return appIconName(for: app)
        case .ciPassing:                            return "checkmark.circle.fill"
        case .gitBranch:                            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var accentColor: Color {
        switch self {
        case .ciFailing:       return .red
        case .watcherAlert:    return .orange
        case .ciRunning:       return .yellow
        case .clipboard:       return .blue
        case .recentActivity:  return .purple
        case .ciPassing:       return .green
        case .gitBranch:       return .cyan
        }
    }

    var title: String {
        switch self {
        case .ciFailing(let repos):
            return repos.count == 1
                ? "\(shortRepoName(repos[0])) failing"
                : "\(repos.count) repos failing"
        case .watcherAlert(let title, _, _, _, let total):
            return total > 1 ? "\(title) (+\(total - 1) more)" : title
        case .ciRunning(let repos):
            return repos.count == 1
                ? "\(shortRepoName(repos[0])) running"
                : "\(repos.count) repos running"
        case .clipboard:
            return "Recently copied"
        case .recentActivity(let app, _, _):
            return app
        case .ciPassing(let count):
            return count == 1 ? "CI passing" : "All \(count) repos passing"
        case .gitBranch(let branch):
            return branch
        }
    }

    var subtitle: String? {
        switch self {
        case .ciFailing(let repos):
            return repos.count == 1 ? nil : repos.map(shortRepoName).joined(separator: ", ")
        case .watcherAlert(_, let summary, _, _, _):
            return summary
        case .ciRunning(let repos):
            return repos.count == 1 ? nil : repos.map(shortRepoName).joined(separator: ", ")
        case .clipboard(let content, _):
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        case .recentActivity(_, let windowTitle, _):
            return windowTitle
        case .ciPassing:
            return nil
        case .gitBranch:
            return "Current branch"
        }
    }

    var prompt: String {
        switch self {
        case .ciFailing:
            return "My CI is failing. Check the status and help me fix it."
        case .watcherAlert(let title, let summary, _, _, _):
            return "I have a new alert: \"\(title)\". \(summary). Help me understand and act on this."
        case .ciRunning:
            return "My CI is currently running. Give me a status update."
        case .clipboard(let content, _):
            let preview = String(content.prefix(200))
            return "I just copied this:\n\n\(preview)\n\nWhat is this? Summarize it for me."
        case .recentActivity(let app, let windowTitle, _):
            var text = "What was I doing in \(app)?"
            if let windowTitle, !windowTitle.isEmpty {
                text += " The window was titled \"\(windowTitle)\"."
            }
            return text
        case .ciPassing:
            return "Give me a full CI status summary across all my repos."
        case .gitBranch(let branch):
            return "What's the status of my current branch \(branch)? Any uncommitted changes?"
        }
    }

    /// Timestamp for display, if applicable.
    var timestamp: Date? {
        switch self {
        case .watcherAlert(_, _, _, let ts, _): return ts
        case .clipboard(_, let ts):             return ts
        case .recentActivity(_, _, let ts):     return ts
        default:                                return nil
        }
    }
}

// MARK: - At a Glance View

struct AtAGlanceView: View {
    let onAction: (String) -> Void

    private let maxCards = 3

    private var glanceItems: [GlanceItem] {
        var items: [GlanceItem] = []

        // CI Status
        let ci = CIStatusMonitor.shared
        switch ci.aggregateStatus {
        case .failing:
            let failingRepos = ci.repoStatuses.filter { $0.value == .failing }.map(\.key)
            items.append(.ciFailing(repos: failingRepos.isEmpty ? ["CI"] : failingRepos))
        case .running:
            let runningRepos = ci.repoStatuses.filter { $0.value == .running }.map(\.key)
            items.append(.ciRunning(repos: runningRepos.isEmpty ? ["CI"] : runningRepos))
        case .passing:
            items.append(.ciPassing(repoCount: max(ci.repoStatuses.count, 1)))
        case .idle, .unknown:
            break
        }

        // Watcher Alerts (undismissed)
        let activeAlerts = WatcherService.shared.alerts.filter { !$0.isDismissed }
        if let top = activeAlerts.first {
            items.append(.watcherAlert(
                title: top.title,
                summary: top.summary,
                type: top.watcherType,
                timestamp: top.timestamp,
                totalCount: activeAlerts.count
            ))
        }

        // Clipboard (only if < 5 min old)
        if let lastClip = ClipboardMonitor.shared.store.entries.first {
            let age = Date().timeIntervalSince(lastClip.timestamp)
            if age < 300 {
                items.append(.clipboard(content: lastClip.content, timestamp: lastClip.timestamp))
            }
        }

        // Git Branch
        if let branch = GitBranchMonitor.shared.currentBranch {
            items.append(.gitBranch(branch: branch))
        }

        // Recent App Activity (always present as fallback)
        if let recent = SessionContextManager.shared.historyStore.sessions.first {
            items.append(.recentActivity(
                appName: recent.appName,
                windowTitle: recent.windowTitle,
                startedAt: recent.startedAt
            ))
        }

        return items.sorted { $0.sortPriority < $1.sortPriority }
            .prefix(maxCards)
            .map { $0 }
    }

    var body: some View {
        let items = glanceItems
        if !items.isEmpty {
            VStack(spacing: 4) {
                ForEach(items) { item in
                    GlanceCardView(item: item) {
                        onAction(item.prompt)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Card View

private struct GlanceCardView: View {
    let item: GlanceItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Accent edge
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.accentColor.opacity(0.8))
                    .frame(width: 2.5)
                    .padding(.vertical, 4)

                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.accentColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 2)

                    if let ts = item.timestamp {
                        Text(timeAgo(ts))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.25))
                            .layoutPriority(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.leading, 5)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Helpers

private func shortRepoName(_ repo: String) -> String {
    repo.components(separatedBy: "/").last ?? repo
}

private func watcherIconName(_ type: String) -> String {
    switch type {
    case "email":   return "envelope.fill"
    case "github":  return "chevron.left.forwardslash.chevron.right"
    default:        return "bell.fill"
    }
}

private func appIconName(for appName: String) -> String {
    let n = appName.lowercased()
    if n.contains("safari")   { return "safari" }
    if n.contains("xcode")    { return "hammer" }
    if n.contains("terminal") { return "terminal" }
    if n.contains("finder")   { return "folder" }
    if n.contains("mail")     { return "envelope" }
    if n.contains("messages") { return "message" }
    if n.contains("slack")    { return "bubble.left.and.bubble.right" }
    if n.contains("chrome") || n.contains("firefox") || n.contains("arc") { return "globe" }
    if n.contains("notes")    { return "note.text" }
    if n.contains("code") || n.contains("cursor") { return "curlybraces" }
    if n.contains("music") || n.contains("spotify") { return "music.note" }
    if n.contains("preview")  { return "doc.richtext" }
    if n.contains("calendar") { return "calendar" }
    return "app.badge"
}
