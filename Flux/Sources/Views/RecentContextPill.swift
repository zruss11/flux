import SwiftUI

struct RecentContextPill: View {
    let session: AppSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: appIcon(for: session.appName))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    if let windowTitle = session.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(timeAgo(session.startedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
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

    private func appIcon(for appName: String) -> String {
        switch appName.lowercased() {
        case let n where n.contains("safari"): return "safari"
        case let n where n.contains("xcode"): return "hammer"
        case let n where n.contains("terminal"): return "terminal"
        case let n where n.contains("finder"): return "folder"
        case let n where n.contains("mail"): return "envelope"
        case let n where n.contains("messages"): return "message"
        case let n where n.contains("slack"): return "bubble.left.and.bubble.right"
        case let n where n.contains("chrome"), let n where n.contains("firefox"), let n where n.contains("arc"):
            return "globe"
        case let n where n.contains("notes"): return "note.text"
        case let n where n.contains("code"), let n where n.contains("cursor"):
            return "curlybraces"
        case let n where n.contains("music"), let n where n.contains("spotify"):
            return "music.note"
        case let n where n.contains("preview"): return "doc.richtext"
        case let n where n.contains("calendar"): return "calendar"
        default: return "app.badge"
        }
    }
}
