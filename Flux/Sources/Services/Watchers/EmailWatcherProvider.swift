import Foundation
import os

/// Polls Gmail API for new/important emails.
///
/// Requires: `gmail_token` credential (OAuth access token).
struct EmailWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .email

    private static let gmailBase = "https://gmail.googleapis.com/gmail/v1/users/me"

    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        guard let token = credentials["gmail_token"], !token.isEmpty else {
            Log.app.warning("EmailWatcher: no gmail_token credential provided")
            return WatcherCheckResult(alerts: [])
        }

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
        let listURL = "\(Self.gmailBase)/messages?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&maxResults=\(maxResults)"

        // List unread messages
        var listReq = URLRequest(url: URL(string: listURL)!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (listData, listResp) = try await URLSession.shared.data(for: listReq)
        guard (listResp as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: listData, encoding: .utf8) ?? ""
            throw WatcherError.apiError("Gmail list failed: \(body)")
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        guard let messageRefs = listJSON?["messages"] as? [[String: Any]], !messageRefs.isEmpty else {
            return WatcherCheckResult(alerts: [], nextState: ["lastCheckEpochMs": "\(Int(Date().timeIntervalSince1970 * 1000))"])
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
            nextState: ["lastCheckEpochMs": "\(Int(Date().timeIntervalSince1970 * 1000))"]
        )
    }

    private func fetchMessageAlert(messageId: String, token: String, config: Watcher) async throws -> WatcherAlert {
        let url = "\(Self.gmailBase)/messages/\(messageId)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date"
        var req = URLRequest(url: URL(string: url)!)
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
            timestamp: ISO8601DateFormatter().date(from: dateStr ?? "") ?? Date(),
            dedupeKey: "email:\(messageId)"
        )
    }

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
