import EventKit
import Foundation
import os

/// Provides calendar operations via EventKit, with AppleScript fallback for UI navigation.
/// Uses EKEventStore for all CRUD operations (no Calendar.app launch required).
actor CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    private init() {}

    // MARK: - Permission

    /// Requests full calendar access. Returns `nil` on success, or a JSON error string on failure.
    private func ensureAccess() async -> String? {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            return nil

        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                if granted {
                    return nil
                }
                return permissionError()
            } catch {
                Log.app.error("Calendar permission request failed: \(error)")
                return permissionError()
            }

        case .denied, .restricted:
            return permissionError()

        case .writeOnly:
            // writeOnly is insufficient for search — request full access.
            return permissionError()

        @unknown default:
            return permissionError()
        }
    }

    private func permissionError() -> String {
        """
        {"ok":false,"error":"Calendar access denied. Please open System Settings > Privacy & Security > Calendars and enable access for Flux, then try again."}
        """
    }

    // MARK: - Public API

    /// Search for calendar events within a date range.
    func searchEvents(
        startDate: String,
        endDate: String,
        query: String? = nil,
        calendarName: String? = nil
    ) async -> String {
        if let error = await ensureAccess() { return error }

        guard let start = parseISO8601(startDate) else {
            return "{\"ok\":false,\"error\":\"Invalid startDate format. Use ISO 8601 (e.g. 2026-02-15T00:00:00-05:00).\"}"
        }
        guard let end = parseISO8601(endDate) else {
            return "{\"ok\":false,\"error\":\"Invalid endDate format. Use ISO 8601 (e.g. 2026-02-15T23:59:59-05:00).\"}"
        }

        var calendars: [EKCalendar]? = nil
        if let calendarName, !calendarName.isEmpty {
            let matching = store.calendars(for: .event).filter { $0.title == calendarName }
            if matching.isEmpty {
                return "{\"ok\":false,\"error\":\"Calendar not found: \(escapeJSON(calendarName))\"}"
            }
            calendars = matching
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)

        // Apply optional text filter.
        let filtered: [EKEvent]
        if let query, !query.isEmpty {
            let q = query.lowercased()
            filtered = events.filter { ($0.title ?? "").lowercased().contains(q) }
        } else {
            filtered = events
        }

        let capped = Array(filtered.prefix(50))
        let items = capped.map { formatEvent($0) }
        return "{\"ok\":true,\"count\":\(items.count),\"events\":[\(items.joined(separator: ","))]}"
    }

    /// Create a new calendar event.
    func addEvent(
        title: String,
        startDate: String,
        endDate: String,
        notes: String? = nil,
        location: String? = nil,
        calendarName: String? = nil,
        isAllDay: Bool = false
    ) async -> String {
        if let error = await ensureAccess() { return error }

        guard let start = parseISO8601(startDate) else {
            return "{\"ok\":false,\"error\":\"Invalid startDate format.\"}"
        }
        guard let end = parseISO8601(endDate) else {
            return "{\"ok\":false,\"error\":\"Invalid endDate format.\"}"
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        if let notes, !notes.isEmpty { event.notes = notes }
        if let location, !location.isEmpty { event.location = location }

        if let calendarName, !calendarName.isEmpty {
            let matching = store.calendars(for: .event).filter { $0.title == calendarName }
            if let cal = matching.first {
                event.calendar = cal
            } else {
                return "{\"ok\":false,\"error\":\"Calendar not found: \(escapeJSON(calendarName))\"}"
            }
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        do {
            try store.save(event, span: .thisEvent)
            let eventId = event.eventIdentifier ?? ""
            return "{\"ok\":true,\"message\":\"Event created successfully.\",\"eventId\":\"\(escapeJSON(eventId))\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"Failed to create event: \(escapeJSON(error.localizedDescription))\"}"
        }
    }

    /// Edit an existing calendar event by identifier.
    func editEvent(
        eventId: String,
        title: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        notes: String? = nil,
        location: String? = nil
    ) async -> String {
        if let error = await ensureAccess() { return error }

        guard let event = store.event(withIdentifier: eventId) else {
            return "{\"ok\":false,\"error\":\"Event not found with id: \(escapeJSON(eventId))\"}"
        }

        if let title, !title.isEmpty { event.title = title }
        if let notes { event.notes = notes }
        if let location { event.location = location }
        if let startDate, let start = parseISO8601(startDate) { event.startDate = start }
        if let endDate, let end = parseISO8601(endDate) { event.endDate = end }

        do {
            try store.save(event, span: .thisEvent)
            return "{\"ok\":true,\"message\":\"Event updated successfully.\",\"eventId\":\"\(escapeJSON(eventId))\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"Failed to update event: \(escapeJSON(error.localizedDescription))\"}"
        }
    }

    /// Delete a calendar event by identifier.
    func deleteEvent(eventId: String) async -> String {
        if let error = await ensureAccess() { return error }

        guard let event = store.event(withIdentifier: eventId) else {
            return "{\"ok\":false,\"error\":\"Event not found with id: \(escapeJSON(eventId))\"}"
        }

        let title = event.title ?? "Untitled"
        do {
            try store.remove(event, span: .thisEvent)
            return "{\"ok\":true,\"message\":\"Event deleted: \(escapeJSON(title))\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"Failed to delete event: \(escapeJSON(error.localizedDescription))\"}"
        }
    }

    /// Open Calendar.app and navigate to a specific date.
    /// This is the only method that uses AppleScript (it needs the Calendar UI).
    func navigateToDate(date: String) async -> String {
        guard let parsedDate = parseISO8601(date) else {
            return "{\"ok\":false,\"error\":\"Invalid date format. Use ISO 8601 (e.g. 2026-03-01).\"}"
        }

        let components = Calendar.current.dateComponents([.year, .month, .day], from: parsedDate)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let day = components.day ?? 1

        let script = """
        tell application "Calendar"
            activate
            set targetDate to current date
            set year of targetDate to \(year)
            set month of targetDate to \(month)
            set day of targetDate to \(day)
            switch view to day view
            view calendar at targetDate
        end tell
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let appleScript = NSAppleScript(source: script)
                var error: NSDictionary?
                appleScript?.executeAndReturnError(&error)

                if let error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    Log.app.error("Calendar navigate error: \(msg)")
                    continuation.resume(returning: "{\"ok\":false,\"error\":\"\(self.escapeJSON(msg))\"}")
                    return
                }

                continuation.resume(returning: "{\"ok\":true,\"message\":\"Calendar opened to \(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))\"}")
            }
        }
    }

    // MARK: - Private Helpers

    private let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let iso8601DateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private func parseISO8601(_ string: String) -> Date? {
        iso8601Full.date(from: string) ?? iso8601DateOnly.date(from: string)
    }

    private let outputFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func formatEvent(_ event: EKEvent) -> String {
        let id = escapeJSON(event.eventIdentifier ?? "")
        let title = escapeJSON(event.title ?? "")
        let start = outputFormatter.string(from: event.startDate)
        let end = outputFormatter.string(from: event.endDate)
        let allDay = event.isAllDay
        let loc = escapeJSON(event.location ?? "")
        let notes = escapeJSON(event.notes ?? "")
        let cal = escapeJSON(event.calendar?.title ?? "")
        return "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"startDate\":\"\(start)\",\"endDate\":\"\(end)\",\"allDay\":\(allDay),\"location\":\"\(loc)\",\"notes\":\"\(notes)\",\"calendar\":\"\(cal)\"}"
    }

    /// Escape a string for safe JSON embedding.
    private nonisolated func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
