import SwiftUI

struct LinearIssuesBoardView: View {
    let issues: [LinearIssueSnapshot]
    let isConfigured: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (LinearIssueSnapshot) -> Void
    let onOpenSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Linear")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if isConfigured {
                    Text("\(issues.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.bottom, 2)

            if !isConfigured {
                setupCard
            } else if isLoading && issues.isEmpty {
                loadingRow
            } else if let errorMessage, issues.isEmpty {
                errorRow(errorMessage)
            } else if issues.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 5) {
                    ForEach(issues) { issue in
                        issueRow(issue)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Linear")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text("Add a Linear API key to show assigned issues here.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

            Text("Linear → Settings → API Tokens")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            Button("Open Settings") {
                onOpenSetup()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var loadingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Loading Linear issues…")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var emptyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(.green.opacity(0.8))
            Text("No active assigned issues")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func issueRow(_ issue: LinearIssueSnapshot) -> some View {
        Button {
            onSelect(issue)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(stateColor(for: issue).opacity(0.2))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .strokeBorder(stateColor(for: issue), lineWidth: 1)
                            .padding(5)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(issue.identifier)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))

                    Text(issue.title)
                        .font(.system(size: 10.8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                Text(issue.stateName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(stateColor(for: issue))

                if issue.priority > 0 {
                    Text(priorityLabel(for: issue.priority))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(priorityColor(for: issue.priority))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func stateColor(for issue: LinearIssueSnapshot) -> Color {
        switch issue.stateType.lowercased() {
        case "completed":
            return .green
        case "canceled", "cancelled":
            return .gray
        case "started", "inprogress", "in_progress":
            return .blue
        case "backlog", "unstarted", "triage":
            return .yellow
        default:
            return .purple
        }
    }

    private func priorityLabel(for value: Int) -> String {
        switch value {
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Med"
        case 4: return "Low"
        default: return "P\(value)"
        }
    }

    private func priorityColor(for value: Int) -> Color {
        switch value {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .gray
        default: return .gray
        }
    }
}
