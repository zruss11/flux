import Foundation
import os

/// Polls GitHub via the `gh` CLI for notifications (PRs, issues, mentions,
/// review requests) and CI/CD workflow failures.
///
/// Requires: The `gh` CLI installed and authenticated (`gh auth login`).
struct GitHubWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .github

    /// Polls GitHub notifications and workflow failures via `gh` CLI.
    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        // Verify gh CLI is available and authenticated.
        let authCheck = try await runGH(["auth", "status", "--active"])
        guard authCheck.exitCode == 0 else {
            Log.app.warning("GitHubWatcher: gh CLI not authenticated — run `gh auth login`")
            return WatcherCheckResult(alerts: [])
        }

        let lastCheckISO = previousState?["lastCheckISO"]
            ?? ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300))

        var alerts: [WatcherAlert] = []

        // 1. Notifications (PRs, issues, mentions, review requests)
        let watchNotifications = config.settings["watchNotifications"] != "false"
        if watchNotifications {
            let notifAlerts = try await checkNotifications(config: config, since: lastCheckISO)
            alerts.append(contentsOf: notifAlerts)
        }

        // 2. CI/CD (failed workflow runs)
        let watchCicd = config.settings["watchCicd"] != "false"
        let repos = config.settings["repos"]?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        if watchCicd && !repos.isEmpty {
            for repo in repos {
                let ciAlerts = try await checkWorkflowRuns(config: config, repo: repo, since: lastCheckISO)
                alerts.append(contentsOf: ciAlerts)
            }
        }

        return WatcherCheckResult(
            alerts: alerts,
            nextState: ["lastCheckISO": ISO8601DateFormatter().string(from: Date())]
        )
    }

    // MARK: - Notifications

    /// Retrieves user notifications from GitHub via `gh api` and maps each into a watcher alert.
    private func checkNotifications(config: Watcher, since: String) async throws -> [WatcherAlert] {
        let encodedSince = since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? since
        let result = try await runGH([
            "api", "notifications",
            "--jq", ".",
            "-f", "since=\(encodedSince)",
            "-f", "all=false",
        ])
        guard result.exitCode == 0, !result.output.isEmpty else { return [] }

        guard let data = result.output.data(using: .utf8),
              let notifications = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return notifications.compactMap { notif in
            notificationToAlert(notif, config: config)
        }
    }

    /// Converts a raw GitHub notification object into a watcher alert.
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
            timestamp: ISO8601DateFormatter().date(from: updatedAt) ?? Date(),
            dedupeKey: "gh-notif:\(id)"
        )
    }

    // MARK: - CI/CD

    /// Retrieves recent failed workflow runs for a repository via `gh run list`.
    private func checkWorkflowRuns(config: Watcher, repo: String, since: String) async throws -> [WatcherAlert] {
        guard let normalizedRepo = validateRepo(repo) else {
            Log.app.warning("GitHubWatcher: skipping invalid repo '\(repo)'")
            return []
        }

        let result = try await runGH([
            "run", "list",
            "--repo", normalizedRepo,
            "--status", "failure",
            "--limit", "5",
            "--json", "databaseId,name,headBranch,updatedAt,conclusion,url,status",
        ])
        guard result.exitCode == 0, !result.output.isEmpty else { return [] }

        guard let data = result.output.data(using: .utf8),
              let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let sinceDate = ISO8601DateFormatter().date(from: since) ?? Date.distantPast

        return runs.compactMap { run -> WatcherAlert? in
            guard let runId = run["databaseId"] as? Int,
                  let name = run["name"] as? String,
                  let branch = run["headBranch"] as? String,
                  let updatedAtStr = run["updatedAt"] as? String,
                  let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr),
                  updatedAt > sinceDate,
                  let htmlUrl = run["url"] as? String else {
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
                summary: "\(normalizedRepo) · Branch: \(branch) · \(conclusion)",
                sourceUrl: htmlUrl,
                suggestedActions: ["View logs", "Retry workflow", "Open PR"],
                timestamp: updatedAt,
                dedupeKey: "gh-ci:\(runId)"
            )
        }
    }

    // MARK: - gh CLI Runner

    private struct GHResult: Sendable {
        let output: String
        let exitCode: Int32
    }

    /// Runs a `gh` CLI command and captures stdout.
    private func runGH(_ arguments: [String]) async throws -> GHResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Inherit PATH so `gh` can be found in common install locations.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: GHResult(output: output, exitCode: process.terminationStatus))
            }
        }
    }

    // MARK: - Helpers

    /// Maps GitHub notification reasons to watcher alert priority.
    private func classifyNotifPriority(reason: String) -> WatcherAlert.Priority {
        switch reason {
        case "review_requested", "assign": return .high
        case "mention", "ci_activity", "comment": return .medium
        case "subscribed", "manual": return .low
        default: return .info
        }
    }

    /// Chooses an emoji marker for notification type and reason.
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

    /// Produces human-readable notification reason text.
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

    /// Returns default action suggestions for a GitHub notification reason.
    private func suggestedActions(for reason: String) -> [String] {
        switch reason {
        case "review_requested": return ["Review PR", "View diff", "Approve"]
        case "assign": return ["View issue", "Start work", "Comment"]
        case "mention": return ["View thread", "Reply"]
        case "ci_activity": return ["View logs", "Retry"]
        default: return ["Open on GitHub"]
        }
    }

    /// Converts supported API resource URLs to equivalent GitHub web URLs.
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

    /// Validates `owner/repo` repo identifiers used for workflow checks.
    private func validateRepo(_ repo: String) -> String? {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }
}
