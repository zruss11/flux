import Foundation
import os

/// Polls Gmail API for new/important emails.
///
/// Requires: `gmail_token` credential (OAuth access token).
struct EmailWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .email

    private static let gmailBase = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// Polls Gmail unread messages and converts new items into watcher alerts.
    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        guard let token = credentials["gmail_token"], !token.isEmpty else {
            Log.app.warning("EmailWatcher: no gmail_token credential provided")
            return WatcherCheckResult(alerts: [])
        }

        let pollStartEpochMs = Int(Date().timeIntervalSince1970 * 1000)
        let lastCheckMs = Int(previousState?["lastCheckEpochMs"] ?? "")
            ?? Int(Date().addingTimeInterval(-300).timeIntervalSince1970 * 1000)
        let afterSeconds = lastCheckMs / 1000
        let parsedMaxResults = Int(config.settings["maxResults"] ?? "") ?? 10
        let maxResults = min(max(parsedMaxResults, 1), 50)
        let labels = (config.settings["labels"] ?? "INBOX")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let labelQuery = labels.isEmpty ? "in:INBOX" : labels.map { "in:\($0)" }.joined(separator: " ")

        let query = "is:unread after:\(afterSeconds) \(labelQuery)"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let listURL = URL(string: "\(Self.gmailBase)/messages?q=\(encodedQuery)&maxResults=\(maxResults)") else {
            throw WatcherError.apiError("Gmail: could not construct list URL")
        }

        // List unread messages
        var listReq = URLRequest(url: listURL)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (listData, listResp) = try await URLSession.shared.data(for: listReq)
        guard (listResp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: listData, encoding: .utf8) ?? ""
            throw WatcherError.apiError("Gmail list failed: \(body)")
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        guard let messageRefs = listJSON?["messages"] as? [[String: Any]], !messageRefs.isEmpty else {
            return WatcherCheckResult(alerts: [], nextState: ["lastCheckEpochMs": "\(pollStartEpochMs)"])
        }

        // Fetch details for each message
        var alerts: [WatcherAlert] = []
        for ref in messageRefs.prefix(maxResults) {
            guard let messageId = ref["id"] as? String else { continue }
            if let alert = try? await fetchMessageAlert(messageId: messageId, token: token, config: config) {
                alerts.append(alert)
            }
        }

        return WatcherCheckResult(
            alerts: alerts,
            nextState: ["lastCheckEpochMs": "\(pollStartEpochMs)"]
        )
    }

    /// Fetches Gmail message metadata and maps it into a watcher alert.
    private func fetchMessageAlert(messageId: String, token: String, config: Watcher) async throws -> WatcherAlert {
        guard let url = URL(string: "\(Self.gmailBase)/messages/\(messageId)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date") else {
            throw WatcherError.apiError("Gmail: could not construct message URL for \(messageId)")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw WatcherError.apiError("Gmail message fetch failed for \(messageId)")
        }
        let msg = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let payload = msg["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: String]] ?? []
        let from = headers.first { $0["name"] == "From" }?["value"] ?? "Unknown"
        let subject = headers.first { $0["name"] == "Subject" }?["value"] ?? "(no subject)"
        let dateStr = headers.first { $0["name"] == "Date" }?["value"]
        let snippet = msg["snippet"] as? String ?? ""
        let labelIds = msg["labelIds"] as? [String] ?? []
        let threadId = msg["threadId"] as? String ?? messageId

        let priority = classifyPriority(labelIds: labelIds, subject: subject, from: from, config: config)

        return WatcherAlert(
            id: UUID().uuidString,
            watcherId: config.id,
            watcherType: "email",
            watcherName: config.name,
            priority: priority,
            title: "📧 \(subject)",
            summary: "From: \(from)\n\(snippet)",
            sourceUrl: "https://mail.google.com/mail/u/0/#inbox/\(threadId)",
            suggestedActions: ["Open in Gmail", "Reply", "Archive"],
            timestamp: Self.parseEmailDate(dateStr) ?? Date(),
            dedupeKey: "email:\(messageId)"
        )
    }

    /// Parses RFC 2822-style email dates from Gmail message headers.
    private static func parseEmailDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(
            of: "\\s*\\(.*\\)$",
            with: "",
            options: .regularExpression
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss zzz",
        ]

        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: normalized) {
                return parsed
            }
        }

        return nil
    }

    /// Assigns priority based on Gmail labels, subject keywords, and optional VIP senders.
    private func classifyPriority(labelIds: [String], subject: String, from: String, config: Watcher) -> WatcherAlert.Priority {
        let subjectLower = subject.lowercased()

        if labelIds.contains("IMPORTANT") { return .high }

        let urgentKeywords = ["urgent", "asap", "critical", "action required", "immediate", "deadline"]
        if urgentKeywords.contains(where: { subjectLower.contains($0) }) { return .high }

        // VIP senders from config
        let vipSenders = config.settings["vipSenders"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let fromLower = from.lowercased()
        if vipSenders.contains(where: { fromLower.contains($0.lowercased()) }) { return .high }

        if labelIds.contains("CATEGORY_PERSONAL") { return .medium }

        return .low
    }
}

enum WatcherError: LocalizedError {
    case apiError(String)
    case missingCredential(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): msg
        case .missingCredential(let key): "Missing credential: \(key)"
        }
    }
}
