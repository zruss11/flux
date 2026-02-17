import SwiftUI

struct WorktreeStatusBoardView: View {
    let snapshots: [WorktreeSnapshot]
    let taskTitleByBranch: [String: String]
    let onSelect: (WorktreeSnapshot) -> Void

    @State private var collapsedLanes: Set<WorktreeLane> = [.done]

    private var sortedLanes: [WorktreeLane] {
        WorktreeLane.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Worktrees")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(snapshots.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.bottom, 2)

            ForEach(sortedLanes, id: \.self) { lane in
                let rows = snapshots.filter { $0.lane == lane }
                laneSection(lane: lane, rows: rows)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func laneSection(lane: WorktreeLane, rows: [WorktreeSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if collapsedLanes.contains(lane) {
                    collapsedLanes.remove(lane)
                } else {
                    collapsedLanes.insert(lane)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: laneIcon(for: lane))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(laneColor(for: lane))

                    Text(lane.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("\(rows.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))

                    Spacer()

                    if !rows.isEmpty {
                        Image(systemName: collapsedLanes.contains(lane) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .buttonStyle(.plain)

            if !collapsedLanes.contains(lane), !rows.isEmpty {
                VStack(spacing: 5) {
                    ForEach(rows) { snapshot in
                        WorktreeStatusRow(
                            snapshot: snapshot,
                            taskTitle: taskTitleByBranch[snapshot.branch]
                        ) {
                            onSelect(snapshot)
                        }
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func laneIcon(for lane: WorktreeLane) -> String {
        switch lane {
        case .inReview: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    private func laneColor(for lane: WorktreeLane) -> Color {
        switch lane {
        case .inReview: return .green
        case .inProgress: return .yellow
        case .done: return .white.opacity(0.75)
        }
    }
}

private struct WorktreeStatusRow: View {
    let snapshot: WorktreeSnapshot
    let taskTitle: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Circle()
                    .fill(ciColor.opacity(0.2))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: ciIcon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ciColor)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(taskTitle ?? snapshot.branch)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let taskTitle, !taskTitle.isEmpty {
                        Text(snapshot.branch)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                if !snapshot.diff.isZero {
                    diffBadge
                }

                if let prNumber = snapshot.prNumber {
                    Text("#\(prNumber)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
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

    private var diffBadge: some View {
        HStack(spacing: 5) {
            if snapshot.diff.additions > 0 {
                Text("+\(snapshot.diff.additions)")
                    .foregroundStyle(.green)
            }

            if snapshot.diff.deletions > 0 {
                Text("-\(snapshot.diff.deletions)")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.75)
        )
    }

    private var ciIcon: String {
        switch snapshot.ciStatus {
        case .passing: return "checkmark"
        case .failing: return "xmark"
        case .running: return "ellipsis"
        case .unknown: return "questionmark"
        }
    }

    private var ciColor: Color {
        switch snapshot.ciStatus {
        case .passing: return .green
        case .failing: return .red
        case .running: return .yellow
        case .unknown: return .gray
        }
    }
}
