import Foundation
import os

/// Polls GitHub API for notifications (PRs, issues, mentions, review requests)
/// and CI/CD workflow failures.
///
/// Requires: `github_token` credential (PAT or OAuth token).
struct GitHubWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .github

    private static let apiBase = "https://api.github.com"

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        guard let token = credentials["github_token"], !token.isEmpty else {
            Log.app.warning("GitHubWatcher: no github_token credential provided")
            return WatcherCheckResult(alerts: [])
        }

        let headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]

        // Capture checkpoint at check START to avoid missing events during the run.
        let checkStartISO = Self.isoFormatter.string(from: Date())

        let lastCheckISO = previousState?["lastCheckISO"]
            ?? Self.isoFormatter.string(from: Date().addingTimeInterval(-300))

        var alerts: [WatcherAlert] = []

        // 1. Notifications (PRs, issues, mentions, review requests)
        let watchNotifications = config.settings["watchNotifications"] != "false"
        if watchNotifications {
            let notifAlerts = try await checkNotifications(config: config, headers: headers, since: lastCheckISO)
            alerts.append(contentsOf: notifAlerts)
        }

        // 2. CI/CD (failed workflow runs)
        let watchCicd = config.settings["watchCicd"] != "false"
        let repos = config.settings["repos"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if watchCicd && !repos.isEmpty {
            for repo in repos {
                let ciAlerts = try await checkWorkflowRuns(config: config, headers: headers, repo: repo, since: lastCheckISO)
                alerts.append(contentsOf: ciAlerts)
            }
        }

        return WatcherCheckResult(
            alerts: alerts,
            nextState: ["lastCheckISO": checkStartISO]
        )
    }

    // MARK: - Notifications

    private func checkNotifications(config: Watcher, headers: [String: String], since: String) async throws -> [WatcherAlert] {
        let urlString = "\(Self.apiBase)/notifications?since=\(since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? since)&all=false"
        guard let url = URL(string: urlString) else {
            throw WatcherError.apiError("GitHubWatcher: invalid notifications URL")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw WatcherError.apiError("GitHub notifications API error (\((resp as? HTTPURLResponse)?.statusCode ?? -1))")
        }

        guard let notifications = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return notifications.compactMap { notif in
            notificationToAlert(notif, config: config)
        }
    }

    private func notificationToAlert(_ notif: [String: Any], config: Watcher) -> WatcherAlert? {
        guard let id = notif["id"] as? String,
              let subject = notif["subject"] as? [String: Any],
              let title = subject["title"] as? String,
              let reason = notif["reason"] as? String,
              let repo = notif["repository"] as? [String: Any],
              let repoFullName = repo["full_name"] as? String,
              let updatedAt = notif["updated_at"] as? String else {
            return nil
        }

        let subjectType = subject["type"] as? String ?? ""
        let apiUrl = subject["url"] as? String ?? ""
        let repoHtmlUrl = repo["html_url"] as? String ?? "https://github.com/\(repoFullName)"
        let emoji = notifTypeEmoji(type: subjectType, reason: reason)
        let priority = classifyNotifPriority(reason: reason)
        let sourceUrl = apiUrlToHtml(apiUrl: apiUrl, repoHtmlUrl: repoHtmlUrl)

        return WatcherAlert(
            id: UUID().uuidString,
            watcherId: config.id,
            watcherType: "github",
            watcherName: config.name,
            priority: priority,
            title: "\(emoji) \(title)",
            summary: "\(repoFullName) · \(formatReason(reason))",
            sourceUrl: sourceUrl,
            suggestedActions: suggestedActions(for: reason),
            timestamp: Self.isoFormatter.date(from: updatedAt) ?? Date(),
            dedupeKey: "gh-notif:\(id)"
        )
    }

    // MARK: - CI/CD

    private func checkWorkflowRuns(config: Watcher, headers: [String: String], repo: String, since: String) async throws -> [WatcherAlert] {
        let urlString = "\(Self.apiBase)/repos/\(repo)/actions/runs?status=failure&per_page=5"
        guard let url = URL(string: urlString) else {
            Log.app.warning("GitHubWatcher: invalid workflow runs URL for repo \(repo)")
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw WatcherError.apiError("GitHub Actions API error for \(repo)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else {
            return []
        }

        let sinceDate = Self.isoFormatter.date(from: since) ?? Date.distantPast

        return runs.compactMap { run -> WatcherAlert? in
            guard let runId = run["id"] as? Int,
                  let name = run["name"] as? String,
                  let branch = run["head_branch"] as? String,
                  let updatedAtStr = run["updated_at"] as? String,
                  let updatedAt = Self.isoFormatter.date(from: updatedAtStr),
                  updatedAt > sinceDate,
                  let htmlUrl = run["html_url"] as? String else {
                return nil
            }

            let conclusion = run["conclusion"] as? String ?? run["status"] as? String ?? "failed"

            return WatcherAlert(
                id: UUID().uuidString,
                watcherId: config.id,
                watcherType: "github",
                watcherName: config.name,
                priority: .high,
                title: "🔴 CI Failed: \(name)",
                summary: "\(repo) · Branch: \(branch) · \(conclusion)",
                sourceUrl: htmlUrl,
                suggestedActions: ["View logs", "Retry workflow", "Open PR"],
                timestamp: updatedAt,
                dedupeKey: "gh-ci:\(runId)"
            )
        }
    }

    // MARK: - Helpers

    private func classifyNotifPriority(reason: String) -> WatcherAlert.Priority {
        switch reason {
        case "review_requested", "assign": return .high
        case "mention", "ci_activity", "comment": return .medium
        case "subscribed", "manual": return .low
        default: return .info
        }
    }

    private func notifTypeEmoji(type: String, reason: String) -> String {
        if reason == "review_requested" { return "👀" }
        if reason == "assign" { return "📌" }
        if reason == "ci_activity" { return "⚡" }

        switch type {
        case "PullRequest": return "🔀"
        case "Issue": return "🐛"
        case "Release": return "🚀"
        case "Discussion": return "💬"
        case "CheckSuite": return "✅"
        default: return "📣"
        }
    }

    private func formatReason(_ reason: String) -> String {
        let map: [String: String] = [
            "review_requested": "Review requested",
            "assign": "Assigned to you",
            "mention": "You were mentioned",
            "comment": "New comment",
            "subscribed": "Subscribed",
            "ci_activity": "CI/CD activity",
            "author": "You authored this",
            "team_mention": "Team mentioned",
            "state_change": "Status changed",
            "security_alert": "Security alert",
        ]
        return map[reason] ?? reason
    }

    private func suggestedActions(for reason: String) -> [String] {
        switch reason {
        case "review_requested": return ["Review PR", "View diff", "Approve"]
        case "assign": return ["View issue", "Start work", "Comment"]
        case "mention": return ["View thread", "Reply"]
        case "ci_activity": return ["View logs", "Retry"]
        default: return ["Open on GitHub"]
        }
    }

    private func apiUrlToHtml(apiUrl: String, repoHtmlUrl: String) -> String {
        // Convert api.github.com/repos/owner/repo/pulls/123 → github.com/owner/repo/pull/123
        guard let range = apiUrl.range(of: #"api\.github\.com/repos/([^/]+/[^/]+)/(pulls|issues|releases)/(\d+)"#, options: .regularExpression) else {
            return repoHtmlUrl
        }

        let match = String(apiUrl[range])
        let parts = match.replacingOccurrences(of: "api.github.com/repos/", with: "").components(separatedBy: "/")
        guard parts.count >= 4 else { return repoHtmlUrl }

        let repo = "\(parts[0])/\(parts[1])"
        let type = parts[2] == "pulls" ? "pull" : parts[2]
        let num = parts[3]
        return "https://github.com/\(repo)/\(type)/\(num)"
    }
}
