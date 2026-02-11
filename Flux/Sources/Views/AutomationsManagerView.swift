import SwiftUI

struct AutomationsManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var automationService = AutomationService.shared
    @State private var editorMode: AutomationEditorMode?
    @State private var pendingDelete: Automation?
    @State private var actionError: String?

    private var sortedAutomations: [Automation] {
        automationService.automations.sorted { lhs, rhs in
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case (.some(let a), .some(let b)):
                if a != b { return a < b }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automations")
                        .font(.headline)
                    Text("Manage recurring agent workflows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editorMode = .create
                } label: {
                    Label("New Automation", systemImage: "plus")
                }
            }

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.1)))
            }

            if sortedAutomations.isEmpty {
                ContentUnavailableView(
                    "No Automations",
                    systemImage: "clock.badge.xmark",
                    description: Text("Create an automation to run agent instructions on a recurring schedule.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedAutomations) { automation in
                            automationCard(automation)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(item: $editorMode) { mode in
            AutomationEditorSheet(mode: mode)
        }
        .confirmationDialog(
            "Delete automation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDelete else { return }
                do {
                    try automationService.deleteAutomation(id: pendingDelete.id)
                    actionError = nil
                } catch {
                    actionError = error.localizedDescription
                }
                self.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.name ?? "")
        }
    }

    private func automationCard(_ automation: Automation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(automation.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(automation.status == .active ? "Active" : "Paused")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(automation.status == .active ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    )

                Spacer()
            }

            Text(automation.prompt)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 12) {
                labelValue(icon: "calendar", title: "Schedule", value: SchedulePreset.fromCron(automation.scheduleExpression).displayString)
            }

            HStack(spacing: 12) {
                labelValue(icon: "clock.arrow.circlepath", title: "Next Run", value: relativeOrNever(automation.nextRunAt))
                labelValue(icon: "clock", title: "Last Run", value: relativeOrNever(automation.lastRunAt))
            }

            if let summary = automation.lastRunSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("Run Now") {
                    do {
                        _ = try automationService.runAutomationNow(id: automation.id)
                        actionError = nil
                    } catch {
                        actionError = error.localizedDescription
                    }
                }

                if automation.status == .active {
                    Button("Pause") {
                        do {
                            _ = try automationService.pauseAutomation(id: automation.id)
                            actionError = nil
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                } else {
                    Button("Resume") {
                        do {
                            _ = try automationService.resumeAutomation(id: automation.id)
                            actionError = nil
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }

                Button("Edit") {
                    editorMode = .edit(automation)
                }

                Button("Open Thread") {
                    openAutomationThread(automation)
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    pendingDelete = automation
                }
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func labelValue(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(title): \(value)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func relativeOrNever(_ date: Date?) -> String {
        guard let date else { return "Not scheduled" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openAutomationThread(_ automation: Automation) {
        guard let conversationId = UUID(uuidString: automation.conversationId) else {
            actionError = "Automation thread ID is invalid."
            return
        }
        actionError = nil

        NotificationCenter.default.post(
            name: .automationOpenThreadRequested,
            object: nil,
            userInfo: [
                NotificationPayloadKey.conversationId: conversationId.uuidString,
                NotificationPayloadKey.conversationTitle: "Automation: \(automation.name)",
            ]
        )
        dismiss()
    }
}

private enum AutomationEditorMode: Identifiable {
    case create
    case edit(Automation)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let automation):
            return "edit-\(automation.id)"
        }
    }
}

private struct AutomationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var automationService = AutomationService.shared

    let mode: AutomationEditorMode

    @State private var name: String
    @State private var prompt: String
    @State private var frequency: EditorFrequency = .weekdays
    @State private var minuteInterval: Int = 30
    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0
    @State private var selectedDays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var selectedDayOfMonth: Int = 1
    @State private var timezoneIdentifier: String
    @State private var errorMessage: String?

    private enum EditorFrequency: String, CaseIterable, Identifiable {
        case everyMinutes = "Every X min"
        case hourly = "Hourly"
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case monthly = "Monthly"

        var id: String { rawValue }
    }

    init(mode: AutomationEditorMode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _prompt = State(initialValue: "")
            _timezoneIdentifier = State(initialValue: TimeZone.current.identifier)
        case .edit(let automation):
            _name = State(initialValue: automation.name)
            _prompt = State(initialValue: automation.prompt)
            _timezoneIdentifier = State(initialValue: automation.timezoneIdentifier)
            let preset = SchedulePreset.fromCron(automation.scheduleExpression)
            switch preset {
            case .everyMinutes(let n):
                _frequency = State(initialValue: .everyMinutes)
                _minuteInterval = State(initialValue: n)
            case .hourly:
                _frequency = State(initialValue: .hourly)
            case .daily(let h, let m):
                _frequency = State(initialValue: .daily)
                _selectedHour = State(initialValue: h)
                _selectedMinute = State(initialValue: m)
            case .weekdays(let h, let m):
                _frequency = State(initialValue: .weekdays)
                _selectedHour = State(initialValue: h)
                _selectedMinute = State(initialValue: m)
            case .weekly(let days, let h, let m):
                _frequency = State(initialValue: .weekly)
                _selectedDays = State(initialValue: days)
                _selectedHour = State(initialValue: h)
                _selectedMinute = State(initialValue: m)
            case .monthly(let d, let h, let m):
                _frequency = State(initialValue: .monthly)
                _selectedDayOfMonth = State(initialValue: d)
                _selectedHour = State(initialValue: h)
                _selectedMinute = State(initialValue: m)
            case .custom:
                _frequency = State(initialValue: .weekly)
                _selectedDays = State(initialValue: Set(Weekday.allCases))
                _selectedHour = State(initialValue: 9)
                _selectedMinute = State(initialValue: 0)
            }
        }
    }

    private var title: String {
        switch mode {
        case .create: return "New Automation"
        case .edit: return "Edit Automation"
        }
    }

    private var canSave: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                        .font(.subheadline)
                    TextField("Automation name", text: $name)
                }
                GridRow(alignment: .top) {
                    Text("Schedule")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(EditorFrequency.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .labelsHidden()

                        scheduleSubFields
                    }
                }
            }
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.subheadline)
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 130)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
    }

    @ViewBuilder
    private var scheduleSubFields: some View {
        switch frequency {
        case .everyMinutes:
            Picker("Interval", selection: $minuteInterval) {
                ForEach([5, 10, 15, 30], id: \.self) { n in
                    Text("\(n) minutes").tag(n)
                }
            }
            .labelsHidden()

        case .hourly:
            EmptyView()

        case .daily, .weekdays:
            timePickerRow

        case .weekly:
            timePickerRow
            HStack(spacing: 4) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(day.shortAbbreviation)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(selectedDays.contains(day) ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                            )
                            .foregroundStyle(selectedDays.contains(day) ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

        case .monthly:
            HStack {
                Picker("Day", selection: $selectedDayOfMonth) {
                    ForEach(1...31, id: \.self) { d in
                        Text("Day \(d)").tag(d)
                    }
                }
                .labelsHidden()
                .frame(width: 100)

                timePickerRow
            }

        }
    }

    private var timePickerRow: some View {
        HStack(spacing: 4) {
            Picker("Hour", selection: $selectedHour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%d %@", h == 0 ? 12 : (h > 12 ? h - 12 : h), h >= 12 ? "PM" : "AM")).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 90)

            Text(":")

            Picker("Minute", selection: $selectedMinute) {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
    }

    private func buildCronExpression() -> String {
        let preset: SchedulePreset
        switch frequency {
        case .everyMinutes:
            preset = .everyMinutes(minuteInterval)
        case .hourly:
            preset = .hourly
        case .daily:
            preset = .daily(hour: selectedHour, minute: selectedMinute)
        case .weekdays:
            preset = .weekdays(hour: selectedHour, minute: selectedMinute)
        case .weekly:
            preset = .weekly(days: selectedDays.isEmpty ? [.monday] : selectedDays, hour: selectedHour, minute: selectedMinute)
        case .monthly:
            preset = .monthly(day: selectedDayOfMonth, hour: selectedHour, minute: selectedMinute)
        }
        return preset.toCron()
    }

    private func save() {
        do {
            switch mode {
            case .create:
                _ = try automationService.createAutomation(
                    name: name,
                    prompt: prompt,
                    scheduleExpression: buildCronExpression(),
                    timezoneIdentifier: timezoneIdentifier
                )
            case .edit(let automation):
                _ = try automationService.updateAutomation(
                    id: automation.id,
                    name: name,
                    prompt: prompt,
                    scheduleExpression: buildCronExpression(),
                    timezoneIdentifier: timezoneIdentifier
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
