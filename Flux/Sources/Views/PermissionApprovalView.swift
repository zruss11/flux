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
    @State private var singleSelectAnswers: [String: String] = [:]
    @State private var multiSelectAnswers: [String: Set<String>] = [:]
    @State private var otherInputs: [String: String] = [:]

    private var normalizedAnswers: [String: String] {
        var combined: [String: String] = [:]
        for q in question.questions {
            if q.multiSelect {
                let selections = multiSelectAnswers[q.question, default: []]
                guard !selections.isEmpty else { continue }
                let mapped = selections.sorted().compactMap { label -> String? in
                    if isOtherOption(label) {
                        let other = trimmedOtherInput(for: q.question)
                        return other.isEmpty ? nil : other
                    }
                    return label
                }
                if !mapped.isEmpty {
                    combined[q.question] = mapped.joined(separator: ", ")
                }
            } else if let selection = singleSelectAnswers[q.question] {
                if isOtherOption(selection) {
                    let other = trimmedOtherInput(for: q.question)
                    if !other.isEmpty {
                        combined[q.question] = other
                    }
                } else {
                    combined[q.question] = selection
                }
            }
        }
        return combined
    }

    private var canSubmit: Bool {
        if singleSelectAnswers.isEmpty && multiSelectAnswers.isEmpty {
            return false
        }
        for q in question.questions {
            if q.multiSelect {
                let selections = multiSelectAnswers[q.question, default: []]
                if selections.contains(where: isOtherOption) && trimmedOtherInput(for: q.question).isEmpty {
                    return false
                }
            } else if let selection = singleSelectAnswers[q.question], isOtherOption(selection) {
                if trimmedOtherInput(for: q.question).isEmpty {
                    return false
                }
            }
        }
        return true
    }

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
                    onSubmit(normalizedAnswers)
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
                            .fill(canSubmit ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
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
                        var selections = multiSelectAnswers[q.question, default: []]
                        if selections.contains(option.label) {
                            selections.remove(option.label)
                            if isOtherOption(option.label) {
                                otherInputs[q.question] = nil
                            }
                        } else {
                            selections.insert(option.label)
                        }
                        if selections.isEmpty {
                            multiSelectAnswers.removeValue(forKey: q.question)
                        } else {
                            multiSelectAnswers[q.question] = selections
                        }
                        singleSelectAnswers.removeValue(forKey: q.question)
                    } else {
                        singleSelectAnswers[q.question] = option.label
                        multiSelectAnswers.removeValue(forKey: q.question)
                        if !isOtherOption(option.label) {
                            otherInputs[q.question] = nil
                        }
                    }
                } label: {
                    let isSelected: Bool = {
                        if q.multiSelect {
                            return multiSelectAnswers[q.question, default: []].contains(option.label)
                        }
                        return singleSelectAnswers[q.question] == option.label
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

                if isOtherOption(option.label) && isOptionSelected(question: q.question, label: option.label, multiSelect: q.multiSelect) {
                    TextField("Type your answer", text: Binding(
                        get: { otherInputs[q.question] ?? "" },
                        set: { otherInputs[q.question] = $0 }
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
        }
    }

    private func trimmedOtherInput(for question: String) -> String {
        otherInputs[question, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOptionSelected(question: String, label: String, multiSelect: Bool) -> Bool {
        if multiSelect {
            return multiSelectAnswers[question, default: []].contains(label)
        }
        return singleSelectAnswers[question] == label
    }

    private func isOtherOption(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("other")
    }
}
