import Foundation

enum Weekday: Int, CaseIterable, Hashable, Comparable, Identifiable {
    case sunday = 0
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6

    var id: Int { rawValue }

    var abbreviation: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }

    var shortAbbreviation: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }

    var cronValue: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SchedulePreset {
    case everyMinutes(Int)
    case hourly
    case daily(hour: Int, minute: Int)
    case weekdays(hour: Int, minute: Int)
    case weekly(days: Set<Weekday>, hour: Int, minute: Int)
    case monthly(day: Int, hour: Int, minute: Int)
    case custom(String)

    func toCron() -> String {
        switch self {
        case .everyMinutes(let n):
            return "*/\(n) * * * *"
        case .hourly:
            return "0 * * * *"
        case .daily(let hour, let minute):
            return "\(minute) \(hour) * * *"
        case .weekdays(let hour, let minute):
            return "\(minute) \(hour) * * 1-5"
        case .weekly(let days, let hour, let minute):
            let dayValues = days.sorted().map { String($0.cronValue) }.joined(separator: ",")
            return "\(minute) \(hour) * * \(dayValues)"
        case .monthly(let day, let hour, let minute):
            return "\(minute) \(hour) \(day) * *"
        case .custom(let expression):
            return expression
        }
    }

    static func fromCron(_ expression: String) -> SchedulePreset {
        let fields = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 else { return .custom(expression) }

        let minuteField = fields[0]
        let hourField = fields[1]
        let domField = fields[2]
        let monthField = fields[3]
        let dowField = fields[4]

        // Must have month = *
        guard monthField == "*" else { return .custom(expression) }

        // */N * * * * → everyMinutes
        if minuteField.hasPrefix("*/"), hourField == "*", domField == "*", dowField == "*" {
            if let n = Int(minuteField.dropFirst(2)), n > 0 {
                return .everyMinutes(n)
            }
        }

        // 0 * * * * → hourly
        if minuteField == "0", hourField == "*", domField == "*", dowField == "*" {
            return .hourly
        }

        // Need specific minute and hour for remaining presets
        guard let minute = Int(minuteField), let hour = Int(hourField) else {
            return .custom(expression)
        }

        // M H * * 1-5 → weekdays
        if domField == "*", dowField == "1-5" {
            return .weekdays(hour: hour, minute: minute)
        }

        // M H * * * → daily
        if domField == "*", dowField == "*" {
            return .daily(hour: hour, minute: minute)
        }

        // M H D * * → monthly (single day-of-month)
        if let day = Int(domField), dowField == "*" {
            return .monthly(day: day, hour: hour, minute: minute)
        }

        // M H * * D,D,... or M H * * D-D → weekly
        if domField == "*" {
            if let days = parseDayOfWeekField(dowField) {
                return .weekly(days: days, hour: hour, minute: minute)
            }
        }

        return .custom(expression)
    }

    var displayString: String {
        switch self {
        case .everyMinutes(let n):
            return "Every \(n) minutes"
        case .hourly:
            return "Every hour"
        case .daily(let hour, let minute):
            return "Daily at \(Self.formatTime(hour: hour, minute: minute))"
        case .weekdays(let hour, let minute):
            return "Weekdays at \(Self.formatTime(hour: hour, minute: minute))"
        case .weekly(let days, let hour, let minute):
            let daysList = days.sorted().map(\.abbreviation).joined(separator: ", ")
            return "\(daysList) at \(Self.formatTime(hour: hour, minute: minute))"
        case .monthly(let day, let hour, let minute):
            return "Monthly on the \(Self.ordinal(day)) at \(Self.formatTime(hour: hour, minute: minute))"
        case .custom(let expression):
            return "Custom (\(expression))"
        }
    }

    var frequencyLabel: String {
        switch self {
        case .everyMinutes: "Every X minutes"
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom: "Custom"
        }
    }

    // MARK: - Private Helpers

    private static func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour: Int
        switch hour {
        case 0: displayHour = 12
        case 1...12: displayHour = hour
        default: displayHour = hour - 12
        }
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        let tens = n % 100
        if tens >= 11 && tens <= 13 {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private static func parseDayOfWeekField(_ field: String) -> Set<Weekday>? {
        var days: Set<Weekday> = []

        let parts = field.split(separator: ",").map(String.init)
        for part in parts {
            if part.contains("-") {
                let rangeParts = part.split(separator: "-", maxSplits: 1).map(String.init)
                guard rangeParts.count == 2,
                      let start = Int(rangeParts[0]),
                      let end = Int(rangeParts[1]),
                      start <= end else {
                    return nil
                }
                for value in start...end {
                    guard let weekday = Weekday(rawValue: value) else { return nil }
                    days.insert(weekday)
                }
            } else {
                guard let value = Int(part),
                      let weekday = Weekday(rawValue: value) else {
                    return nil
                }
                days.insert(weekday)
            }
        }

        return days.isEmpty ? nil : days
    }
}
