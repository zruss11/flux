import Foundation

struct AutomationDispatchRequest {
    let automationId: String
    let conversationId: String
    let content: String
}

enum AutomationError: LocalizedError {
    case notFound(String)
    case emptyPrompt
    case invalidSchedule(String)
    case invalidTimezone(String)
    case noNextRun(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Automation not found: \(id)"
        case .emptyPrompt:
            return "Automation prompt cannot be empty."
        case .invalidSchedule(let message):
            return "Invalid schedule expression: \(message)"
        case .invalidTimezone(let identifier):
            return "Invalid timezone identifier: \(identifier)"
        case .noNextRun(let expression):
            return "Could not compute a next run for schedule expression: \(expression)"
        }
    }
}

@MainActor
@Observable
final class AutomationService {
    static let shared = AutomationService()

    private(set) var automations: [Automation] = []
    private(set) var isSchedulerRunning = false

    private var schedulerTask: Task<Void, Never>?
    private var dispatchHandler: ((AutomationDispatchRequest) -> Void)?
    private let schedulerPollIntervalSeconds: UInt64 = 30

    private struct StoreEnvelope: Codable {
        let version: Int
        let automations: [Automation]
    }

    private static var automationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/automations", isDirectory: true)
    }

    private static var storageURL: URL {
        automationsDirectory.appendingPathComponent("automations.json")
    }

    init() {
        load()
        normalizeSchedulesAfterLoad()
    }

    var activeCount: Int {
        automations.filter { $0.status == .active }.count
    }

    func configureRunner(_ handler: @escaping (AutomationDispatchRequest) -> Void) {
        dispatchHandler = handler
        startSchedulerIfNeeded()
    }

    func createAutomation(
        name: String?,
        prompt: String,
        scheduleExpression: String,
        timezoneIdentifier: String?
    ) throws -> Automation {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            throw AutomationError.emptyPrompt
        }

        let normalizedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedName.isEmpty ? Self.defaultName(from: normalizedPrompt) : normalizedName
        let timezoneId = normalizeTimezoneIdentifier(timezoneIdentifier)
        let timezone = try resolveTimeZone(identifier: timezoneId)

        let schedule = try CronSchedule(expression: scheduleExpression)
        guard let nextRun = schedule.nextRun(after: Date(), in: timezone) else {
            throw AutomationError.noNextRun(scheduleExpression)
        }

        var automation = Automation(
            name: title,
            prompt: normalizedPrompt,
            scheduleExpression: schedule.expression,
            timezoneIdentifier: timezone.identifier,
            status: .active,
            createdAt: Date(),
            updatedAt: Date(),
            nextRunAt: nextRun
        )
        automation.lastRunSummary = "Created. Next run scheduled."

        automations.insert(automation, at: 0)
        save()
        return automation
    }

    func updateAutomation(
        id: String,
        name: String?,
        prompt: String?,
        scheduleExpression: String?,
        timezoneIdentifier: String?
    ) throws -> Automation {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw AutomationError.notFound(id)
        }

        var updated = automations[index]

        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.name = trimmed.isEmpty ? Self.defaultName(from: updated.prompt) : trimmed
        }

        if let prompt {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AutomationError.emptyPrompt
            }
            updated.prompt = trimmed
            if name == nil && updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.name = Self.defaultName(from: trimmed)
            }
        }

        if let timezoneIdentifier {
            let timezoneId = normalizeTimezoneIdentifier(timezoneIdentifier)
            let timezone = try resolveTimeZone(identifier: timezoneId)
            updated.timezoneIdentifier = timezone.identifier
        }

        if let scheduleExpression {
            let schedule = try CronSchedule(expression: scheduleExpression)
            updated.scheduleExpression = schedule.expression
        }

        if updated.status == .active {
            let timezone = try resolveTimeZone(identifier: updated.timezoneIdentifier)
            let schedule = try CronSchedule(expression: updated.scheduleExpression)
            guard let nextRun = schedule.nextRun(after: Date(), in: timezone) else {
                throw AutomationError.noNextRun(updated.scheduleExpression)
            }
            updated.nextRunAt = nextRun
        }

        updated.updatedAt = Date()
        updated.lastRunSummary = "Updated."

        automations[index] = updated
        save()
        return updated
    }

    func pauseAutomation(id: String) throws -> Automation {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw AutomationError.notFound(id)
        }
        automations[index].status = .paused
        automations[index].nextRunAt = nil
        automations[index].updatedAt = Date()
        automations[index].lastRunSummary = "Paused."
        save()
        return automations[index]
    }

    func resumeAutomation(id: String) throws -> Automation {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw AutomationError.notFound(id)
        }

        let timezone = try resolveTimeZone(identifier: automations[index].timezoneIdentifier)
        let schedule = try CronSchedule(expression: automations[index].scheduleExpression)
        guard let nextRun = schedule.nextRun(after: Date(), in: timezone) else {
            throw AutomationError.noNextRun(automations[index].scheduleExpression)
        }

        automations[index].status = .active
        automations[index].nextRunAt = nextRun
        automations[index].updatedAt = Date()
        automations[index].lastRunSummary = "Resumed."
        save()
        return automations[index]
    }

    func deleteAutomation(id: String) throws {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw AutomationError.notFound(id)
        }
        automations.remove(at: index)
        save()
    }

    func runAutomationNow(id: String) throws -> Automation {
        guard let index = automations.firstIndex(where: { $0.id == id }) else {
            throw AutomationError.notFound(id)
        }
        return try dispatchAutomation(at: index, reason: "manual")
    }

    private func startSchedulerIfNeeded() {
        guard schedulerTask == nil else { return }
        isSchedulerRunning = true

        schedulerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.runDueAutomations()
                try? await Task.sleep(nanoseconds: self.schedulerPollIntervalSeconds * 1_000_000_000)
            }
        }
    }

    private func runDueAutomations() {
        let now = Date()
        var changed = false
        for index in automations.indices {
            guard automations[index].status == .active else { continue }
            guard let nextRun = automations[index].nextRunAt else { continue }
            guard nextRun <= now else { continue }
            do {
                _ = try dispatchAutomation(at: index, reason: "scheduled")
            } catch {
                automations[index].status = .paused
                automations[index].nextRunAt = nil
                automations[index].updatedAt = now
                automations[index].lastRunSummary = "Paused due to schedule error: \(error.localizedDescription)"
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    @discardableResult
    private func dispatchAutomation(at index: Int, reason: String) throws -> Automation {
        var automation = automations[index]
        let now = Date()

        // Legacy data may contain non-UUID conversation ids. Normalize before dispatch.
        if UUID(uuidString: automation.conversationId) == nil {
            automation.conversationId = UUID().uuidString
        }

        let timezone = try resolveTimeZone(identifier: automation.timezoneIdentifier)
        let schedule = try CronSchedule(expression: automation.scheduleExpression)
        let nextRun = schedule.nextRun(after: now, in: timezone)

        automation.lastRunAt = now
        automation.nextRunAt = nextRun
        automation.updatedAt = now

        let dispatchMessage = Self.dispatchContent(
            for: automation,
            runReason: reason,
            timestamp: now,
            timezone: timezone
        )

        if dispatchHandler != nil {
            automation.lastRunSummary = reason == "manual"
                ? "Ran manually."
                : "Scheduled run dispatched."
            dispatchHandler?(AutomationDispatchRequest(
                automationId: automation.id,
                conversationId: automation.conversationId,
                content: dispatchMessage
            ))
        } else {
            automation.lastRunSummary = "Skipped run because automation runner is unavailable."
        }

        if automation.status == .active && automation.nextRunAt == nil {
            automation.status = .paused
            automation.lastRunSummary = "Paused automatically because the next run could not be computed."
        }

        automations[index] = automation
        save()
        return automation
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else {
            automations = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(StoreEnvelope.self, from: data) {
            automations = envelope.automations
            return
        }

        // Backward-compatible fallback for early local builds that may have saved plain arrays.
        if let legacy = try? decoder.decode([Automation].self, from: data) {
            automations = legacy
            return
        }

        automations = []
    }

    private func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.automationsDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let envelope = StoreEnvelope(version: 1, automations: automations)
        if let data = try? encoder.encode(envelope) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }

    private func normalizeSchedulesAfterLoad() {
        var changed = false
        let now = Date()

        for index in automations.indices {
            var automation = automations[index]

            do {
                if UUID(uuidString: automation.conversationId) == nil {
                    automation.conversationId = UUID().uuidString
                    changed = true
                }

                let timezone = try resolveTimeZone(identifier: automation.timezoneIdentifier)
                let schedule = try CronSchedule(expression: automation.scheduleExpression)
                if automation.scheduleExpression != schedule.expression {
                    automation.scheduleExpression = schedule.expression
                    changed = true
                }

                if automation.status == .active {
                    if let next = automation.nextRunAt, next > now {
                        // Keep future schedule.
                    } else {
                        automation.nextRunAt = schedule.nextRun(after: now, in: timezone)
                        changed = true
                    }
                }
            } catch {
                automation.status = .paused
                automation.nextRunAt = nil
                automation.lastRunSummary = "Paused due to invalid schedule/timezone."
                changed = true
            }

            automations[index] = automation
        }

        if changed {
            save()
        }
    }

    private func normalizeTimezoneIdentifier(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TimeZone.current.identifier : trimmed
    }

    private func resolveTimeZone(identifier: String) throws -> TimeZone {
        guard let timezone = TimeZone(identifier: identifier) else {
            throw AutomationError.invalidTimezone(identifier)
        }
        return timezone
    }

    private static func defaultName(from prompt: String) -> String {
        let singleLine = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !singleLine.isEmpty else { return "Automation" }
        if singleLine.count <= 52 { return singleLine }
        return String(singleLine.prefix(52)) + "..."
    }

    private static func dispatchContent(
        for automation: Automation,
        runReason: String,
        timestamp: Date,
        timezone: TimeZone
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timezone

        let triggerLabel = runReason == "manual" ? "manual" : "scheduled"
        return """
        [AUTOMATION RUN]
        Name: \(automation.name)
        Automation ID: \(automation.id)
        Trigger: \(triggerLabel)
        Triggered At: \(formatter.string(from: timestamp))

        Execute the following instructions now:
        \(automation.prompt)
        """
    }
}

private struct CronSchedule {
    let expression: String
    private let minute: Set<Int>
    private let hour: Set<Int>
    private let dayOfMonth: Set<Int>
    private let month: Set<Int>
    private let dayOfWeek: Set<Int>
    private let dayOfMonthWildcard: Bool
    private let dayOfWeekWildcard: Bool

    init(expression: String) throws {
        let normalized = expression
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard normalized.count == 5 else {
            throw AutomationError.invalidSchedule("Expected 5 fields (`minute hour day month weekday`).")
        }

        self.expression = normalized.joined(separator: " ")
        minute = try Self.parseField(normalized[0], min: 0, max: 59, label: "minute")
        hour = try Self.parseField(normalized[1], min: 0, max: 23, label: "hour")
        dayOfMonth = try Self.parseField(normalized[2], min: 1, max: 31, label: "day-of-month")
        month = try Self.parseField(
            normalized[3],
            min: 1,
            max: 12,
            label: "month",
            aliases: [
                "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
                "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
            ]
        )
        dayOfWeek = try Self.parseField(
            normalized[4],
            min: 0,
            max: 7,
            label: "day-of-week",
            aliases: [
                "SUN": 0, "MON": 1, "TUE": 2, "WED": 3, "THU": 4, "FRI": 5, "SAT": 6,
            ],
            mapSevenToZero: true
        )

        dayOfMonthWildcard = Self.isWildcard(normalized[2])
        dayOfWeekWildcard = Self.isWildcard(normalized[4])
    }

    func nextRun(after date: Date, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var candidate = calendar.date(bySetting: .second, value: 0, of: date) ?? date
        if candidate <= date {
            guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else { return nil }
            candidate = next
        }

        let maxIterations = 60 * 24 * 366 * 2 // two years
        for _ in 0..<maxIterations {
            if matches(candidate, in: calendar) {
                return candidate
            }
            guard let next = calendar.date(byAdding: .minute, value: 1, to: candidate) else { break }
            candidate = next
        }
        return nil
    }

    private func matches(_ date: Date, in calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let minuteValue = components.minute,
              let hourValue = components.hour,
              let dayValue = components.day,
              let monthValue = components.month,
              let weekdayRaw = components.weekday else {
            return false
        }

        guard minute.contains(minuteValue),
              hour.contains(hourValue),
              month.contains(monthValue) else {
            return false
        }

        let weekday = weekdayRaw - 1 // Calendar weekday: 1=Sunday ... 7=Saturday
        let dayOfMonthMatch = dayOfMonth.contains(dayValue)
        let dayOfWeekMatch = dayOfWeek.contains(weekday)

        if dayOfMonthWildcard && dayOfWeekWildcard {
            return true
        }
        if dayOfMonthWildcard {
            return dayOfWeekMatch
        }
        if dayOfWeekWildcard {
            return dayOfMonthMatch
        }

        // Cron semantics: when both fields are restricted, either may match.
        return dayOfMonthMatch || dayOfWeekMatch
    }

    private static func isWildcard(_ field: String) -> Bool {
        field.trimmingCharacters(in: .whitespacesAndNewlines) == "*"
    }

    private static func parseField(
        _ rawValue: String,
        min: Int,
        max: Int,
        label: String,
        aliases: [String: Int] = [:],
        mapSevenToZero: Bool = false
    ) throws -> Set<Int> {
        let upper = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else {
            throw AutomationError.invalidSchedule("\(label) field is empty.")
        }

        let pieces = upper.split(separator: ",").map(String.init)
        var values: Set<Int> = []

        for piece in pieces {
            let stepParts = piece.split(separator: "/", maxSplits: 1).map(String.init)
            guard stepParts.count <= 2 else {
                throw AutomationError.invalidSchedule("Invalid step syntax in \(label): \(piece)")
            }

            let base = stepParts[0]
            let step: Int
            if stepParts.count == 2 {
                guard let parsedStep = Int(stepParts[1]), parsedStep > 0 else {
                    throw AutomationError.invalidSchedule("Invalid step value in \(label): \(piece)")
                }
                step = parsedStep
            } else {
                step = 1
            }

            let baseValues = try parseBaseValues(
                base,
                min: min,
                max: max,
                label: label,
                aliases: aliases,
                mapSevenToZero: mapSevenToZero
            )
            guard !baseValues.isEmpty else {
                throw AutomationError.invalidSchedule("No values available in \(label): \(piece)")
            }

            let start = baseValues[0]
            for value in baseValues where (value - start) % step == 0 {
                let normalized = mapSevenToZero && value == 7 ? 0 : value
                values.insert(normalized)
            }
        }

        if values.isEmpty {
            throw AutomationError.invalidSchedule("No values parsed for \(label).")
        }
        return values
    }

    private static func parseBaseValues(
        _ raw: String,
        min: Int,
        max: Int,
        label: String,
        aliases: [String: Int],
        mapSevenToZero: Bool
    ) throws -> [Int] {
        if raw == "*" {
            let upperBound = mapSevenToZero ? max - 1 : max
            return Array(min...upperBound)
        }

        if raw.contains("-") {
            let parts = raw.split(separator: "-", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw AutomationError.invalidSchedule("Invalid range in \(label): \(raw)")
            }
            let start = try parseValue(parts[0], min: min, max: max, label: label, aliases: aliases, mapSevenToZero: mapSevenToZero)
            let end = try parseValue(parts[1], min: min, max: max, label: label, aliases: aliases, mapSevenToZero: mapSevenToZero)
            guard start <= end else {
                throw AutomationError.invalidSchedule("Descending ranges are not supported in \(label): \(raw)")
            }
            return Array(start...end)
        }

        let value = try parseValue(raw, min: min, max: max, label: label, aliases: aliases, mapSevenToZero: mapSevenToZero)
        return [value]
    }

    private static func parseValue(
        _ raw: String,
        min: Int,
        max: Int,
        label: String,
        aliases: [String: Int],
        mapSevenToZero: Bool
    ) throws -> Int {
        if let aliased = aliases[raw] {
            return aliased
        }

        guard let numeric = Int(raw) else {
            throw AutomationError.invalidSchedule("Invalid numeric value in \(label): \(raw)")
        }

        let upperBound = mapSevenToZero ? max : max
        guard numeric >= min && numeric <= upperBound else {
            throw AutomationError.invalidSchedule("Value out of range in \(label): \(raw)")
        }
        return numeric
    }
}
