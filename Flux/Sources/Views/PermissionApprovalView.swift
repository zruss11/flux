import SwiftUI

// MARK: - Permission Approval Card

/// Inline chat card for tool permission approvals. Shows tool name, key input details,
/// and Allow/Deny action buttons. Resolves to a checkmark or xmark after response.
struct PermissionApprovalCard: View {
    let request: PendingPermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void

    private var displayName: String {
        request.toolName
            .replacingOccurrences(of: "__", with: " → ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var primaryDetail: String? {
        let candidates = ["command", "file_path", "path", "url", "query", "content"]
        for key in candidates {
            if let value = request.input[key], !value.isEmpty {
                return value
            }
        }
        return request.input.values.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))

                Text("Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                if request.status != .pending {
                    statusBadge
                }
            }

            // Tool name badge
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            }

            // Input preview
            if let detail = primaryDetail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            // Action buttons (only when pending)
            if request.status == .pending {
                HStack(spacing: 8) {
                    Button {
                        onAllow()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Allow")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDeny()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Deny")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch request.status {
        case .approved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("Allowed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.green.opacity(0.8))
        case .denied:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                Text("Denied")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.red.opacity(0.7))
        case .pending:
            EmptyView()
        }
    }
}

// MARK: - Ask User Question Card

/// Inline chat card for clarifying questions from the agent. Shows selectable options
/// with single/multi-select support and a submit button.
struct AskUserQuestionCard: View {
    let question: PendingAskUserQuestion
    let onSubmit: ([String: String]) -> Void
    @State private var selectedAnswers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue.opacity(0.9))

                Text("Flux has a question")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                if question.status == .answered {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Answered")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.green.opacity(0.8))
                }
            }

            if question.status == .pending {
                ForEach(question.questions) { q in
                    questionSection(q)
                }

                Button {
                    onSubmit(selectedAnswers)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("Submit")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedAnswers.isEmpty ? Color.blue.opacity(0.15) : Color.blue.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedAnswers.isEmpty)
            } else {
                // Show submitted answers
                ForEach(Array(question.answers.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(value)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func questionSection(_ q: PendingAskUserQuestion.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(q.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            ForEach(q.options) { option in
                Button {
                    if q.multiSelect {
                        let currentValue = selectedAnswers[q.question] ?? ""
                        let labels = currentValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        if labels.contains(option.label) {
                            let filtered = labels.filter { $0 != option.label }
                            selectedAnswers[q.question] = filtered.joined(separator: ", ")
                            if filtered.isEmpty { selectedAnswers.removeValue(forKey: q.question) }
                        } else {
                            let updated = labels + [option.label]
                            selectedAnswers[q.question] = updated.joined(separator: ", ")
                        }
                    } else {
                        selectedAnswers[q.question] = option.label
                    }
                } label: {
                    let isSelected: Bool = {
                        guard let current = selectedAnswers[q.question] else { return false }
                        if q.multiSelect {
                            return current.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(option.label)
                        }
                        return current == option.label
                    }()

                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? (q.multiSelect ? "checkmark.square.fill" : "circle.inset.filled") : (q.multiSelect ? "square" : "circle"))
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? .blue.opacity(0.9) : .white.opacity(0.4))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.7))
                            if let desc = option.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
