import Foundation
import SQLite3
import os

/// Watches Apple's macOS notification database for new notifications.
///
/// The usernoted SQLite database at
/// `~/Library/Group Containers/group.com.apple.usernoted/db2/db`
/// records every delivered notification regardless of Focus / DND state.
/// This gives Flux a reliable second path for notification awareness —
/// the Accessibility observer can miss notifications in Focus mode, but
/// the DB is always written to.
///
/// **IMPORTANT SECURITY NOTE**: This provider requires Full Disk Access (FDA)
/// permission for the app to read Apple's notification database. Without FDA,
/// the provider will gracefully fail with a warning and return empty results.
/// Users should be informed that enabling FDA allows the app to access sensitive
/// system databases. The implementation only reads notification data and does
/// not modify or access other sensitive files.
struct NotificationDBWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .notificationDB

    /// Path to Apple's usernoted notification database.
    private static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }()

    /// Maximum number of notifications to return per check.
    private let maxResultsPerCheck = 20

    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        let dbPath = Self.dbPath

        // Verify the database is accessible.
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            Log.app.warning("NotificationDBWatcher: cannot read database at \(dbPath) — Full Disk Access may be required")
            return WatcherCheckResult(alerts: [])
        }

        // Open the SQLite database read-only.
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.app.warning("NotificationDBWatcher: failed to open database — \(errMsg)")
            sqlite3_close(db)
            return WatcherCheckResult(alerts: [])
        }
        defer { sqlite3_close(db) }

        // Determine the checkpoint: last delivered_date we've seen.
        let lastEpoch = Double(previousState?["lastDeliveredDate"] ?? "") ?? Date().addingTimeInterval(-120).timeIntervalSince1970

        // Query recent notifications delivered after the checkpoint.
        let alerts = queryNewNotifications(db: db, since: lastEpoch, config: config)

        // Compute the new checkpoint from the latest notification we saw.
        let latestEpoch = alerts.map(\.timestamp.timeIntervalSince1970).max() ?? lastEpoch

        return WatcherCheckResult(
            alerts: alerts,
            nextState: ["lastDeliveredDate": "\(latestEpoch)"]
        )
    }

    // MARK: - SQLite Query

    /// Reads new notification rows from the `record` table.
    private func queryNewNotifications(db: OpaquePointer, since epoch: Double, config: Watcher) -> [WatcherAlert] {
        // The usernoted DB stores notifications in the `record` table.
        // Columns of interest: app (bundle ID), uuid, data (bplist), delivered_date, presented.
        // `delivered_date` is a Core Data timestamp (seconds since 2001-01-01 00:00:00 UTC).
        let coreDataOffset: Double = 978_307_200  // Seconds between Unix epoch and 2001-01-01
        let sinceCD = epoch - coreDataOffset

        let query = """
            SELECT app, uuid, data, delivered_date, presented
            FROM record
            WHERE delivered_date > ?
            ORDER BY delivered_date DESC
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            Log.app.warning("NotificationDBWatcher: query prepare failed — \(errMsg)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_bind_double(stmt, 1, sinceCD) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, Int32(maxResultsPerCheck)) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            Log.app.warning("NotificationDBWatcher: bind parameters failed — \(errMsg)")
            return []
        }

        var alerts: [WatcherAlert] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let appId = columnText(stmt, index: 0) ?? "unknown"
            let uuid = columnText(stmt, index: 1) ?? UUID().uuidString
            let deliveredDateCD = sqlite3_column_double(stmt, 3)
            let deliveredDate = Date(timeIntervalSince1970: deliveredDateCD + coreDataOffset)

            // Decode the bplist data blob for title and body.
            var title = appDisplayName(for: appId)
            var body = ""

            if let dataBlob = columnBlob(stmt, index: 2) {
                let decoded = decodeBplist(dataBlob)
                if let t = decoded.title, !t.isEmpty { title = t }
                if let b = decoded.body { body = b }
            }

            let priority = classifyPriority(appId: appId)

            alerts.append(WatcherAlert(
                id: UUID().uuidString,
                watcherId: config.id,
                watcherType: "notificationDB",
                watcherName: config.name,
                priority: priority,
                title: "🔔 \(title)",
                summary: body.isEmpty ? "Notification from \(appDisplayName(for: appId))" : body,
                suggestedActions: ["View", "Dismiss"],
                timestamp: deliveredDate,
                dedupeKey: "notifdb:\(uuid)"
            ))
        }

        return alerts
    }

    // MARK: - Bplist Decoding

    private struct DecodedNotification {
        var title: String?
        var body: String?
    }

    /// Attempts to decode the notification bplist data blob.
    /// Apple stores notification content as a binary plist; we try to extract
    /// title and body fields via NSKeyedUnarchiver/PropertyListSerialization.
    private func decodeBplist(_ data: Data) -> DecodedNotification {
        var result = DecodedNotification()

        // Validate data size to prevent excessive memory usage
        guard data.count > 0 && data.count < 1_048_576 else { // Max 1MB
            return result
        }

        // Try PropertyListSerialization first (handles most cases).
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return result
        }

        // The bplist may be a dictionary at the top level, or an NSKeyedArchiver archive.
        if let dict = plist as? [String: Any] {
            result.title = extractString(from: dict, keys: ["titl", "title", "titl"])
            result.body = extractString(from: dict, keys: ["body", "subt", "subtitle"])

            // Sometimes nested under "req" or "aps"
            if let req = dict["req"] as? [String: Any] {
                if result.title == nil { result.title = extractString(from: req, keys: ["titl", "title"]) }
                if result.body == nil { result.body = extractString(from: req, keys: ["body", "subt"]) }
            }
            if let aps = dict["aps"] as? [String: Any] {
                if let alert = aps["alert"] as? [String: Any] {
                    if result.title == nil { result.title = extractString(from: alert, keys: ["title"]) }
                    if result.body == nil { result.body = extractString(from: alert, keys: ["body"]) }
                } else if let alertStr = aps["alert"] as? String {
                    if result.body == nil { result.body = alertStr }
                }
            }
        }

        return result
    }

    private func extractString(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - SQLite Column Helpers

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func columnBlob(_ stmt: OpaquePointer?, index: Int32) -> Data? {
        guard let blob = sqlite3_column_blob(stmt, index) else { return nil }
        let length = sqlite3_column_bytes(stmt, index)
        guard length > 0 else { return nil }
        return Data(bytes: blob, count: Int(length))
    }

    // MARK: - Priority Classification

    /// Maps known bundle IDs to alert priorities.
    private func classifyPriority(appId: String) -> WatcherAlert.Priority {
        let lowered = appId.lowercased()

        // High priority: direct communication apps
        let highPriorityApps = [
            "com.apple.mobilephone",
            "com.apple.facetime",
            "com.apple.mobilesms",
            "com.apple.messages",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.teams",
        ]
        if highPriorityApps.contains(where: { lowered.contains($0) }) { return .high }

        // Medium priority: productivity / calendar
        let mediumPriorityApps = [
            "com.apple.ical",
            "com.apple.reminders",
            "com.apple.mail",
            "com.readdle.smartemail",
        ]
        if mediumPriorityApps.contains(where: { lowered.contains($0) }) { return .medium }

        return .info
    }

    // MARK: - App Display Name

    /// Returns a human-readable app name from a bundle identifier.
    private func appDisplayName(for bundleId: String) -> String {
        // Well-known bundle IDs → friendly names.
        let knownApps: [String: String] = [
            "com.apple.mobilesms": "Messages",
            "com.apple.messages": "Messages",
            "com.apple.mail": "Mail",
            "com.apple.ical": "Calendar",
            "com.apple.reminders": "Reminders",
            "com.apple.facetime": "FaceTime",
            "com.apple.mobilephone": "Phone",
            "com.apple.Safari": "Safari",
            "com.apple.finder": "Finder",
            "com.apple.Notes": "Notes",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.microsoft.teams": "Teams",
            "com.microsoft.Outlook": "Outlook",
        ]
        if let name = knownApps[bundleId] { return name }

        // Fallback: extract last component of bundle ID.
        let components = bundleId.components(separatedBy: ".")
        if let last = components.last, !last.isEmpty {
            return last.capitalized
        }
        return bundleId
    }
}
