import Foundation
import CryptoKit
import os

/// Generic HTTP polling watcher with change detection and keyword matching.
///
/// Configuration via `settings`:
///   - `url` — URL to poll
///   - `prompt` — description of what to watch for
///   - `method` — HTTP method (default: GET)
///   - `keywords` — comma-separated keywords to match in response
///   - `alertOnError` — "true" to emit alert when fetch fails
///
/// Credentials: `api_token` used as Bearer token if provided.
struct CustomWatcherProvider: WatcherProvider {
    let type: Watcher.WatcherType = .custom

    /// Maximum response body size for comparison.
    private let maxBodyChars = 8000

    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult {
        let url = config.settings["url"]
        let prompt = config.settings["prompt"] ?? ""
        let method = config.settings["method"] ?? "GET"

        var responseBody: String?

        // Fetch URL if specified
        if let urlString = url, let fetchURL = URL(string: urlString) {
            do {
                var req = URLRequest(url: fetchURL)
                req.httpMethod = method
                req.timeoutInterval = 30

                if let token = credentials["api_token"], !token.isEmpty {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw WatcherError.apiError("HTTP \(http.statusCode)")
                }
                var body = String(data: data, encoding: .utf8) ?? ""
                if body.count > maxBodyChars {
                    body = String(body.prefix(maxBodyChars)) + "\n[... truncated]"
                }
                responseBody = body
            } catch {
                Log.app.error("CustomWatcher fetch failed for \(urlString): \(error.localizedDescription)")

                if config.settings["alertOnError"] == "true" {
                    return WatcherCheckResult(alerts: [
                        WatcherAlert(
                            id: UUID().uuidString,
                            watcherId: config.id,
                            watcherType: "custom",
                            watcherName: config.name,
                            priority: .medium,
                            title: "⚠️ \(config.name): Fetch failed",
                            summary: "Could not reach \(urlString): \(error.localizedDescription)",
                            sourceUrl: urlString,
                            timestamp: Date(),
                            dedupeKey: "custom-fetch-error:\(config.id):\(errorBucketKey(for: config))"
                        )
                    ])
                }
                return WatcherCheckResult(alerts: [])
            }
        }

        let currentDigest = stableDigest(responseBody ?? "")
        let alerts = evaluate(
            config: config,
            currentBody: responseBody,
            currentDigest: currentDigest,
            previousState: previousState,
            prompt: prompt
        )

        return WatcherCheckResult(
            alerts: alerts,
            nextState: [
                "lastBodyDigest": currentDigest,
                "lastBodySnippet": responseBody.map { String($0.prefix(2000)) } ?? "",
                "lastCheckAt": "\(Int(Date().timeIntervalSince1970))",
            ]
        )
    }

    // MARK: - Evaluation

    private func evaluate(
        config: Watcher,
        currentBody: String?,
        currentDigest: String,
        previousState: [String: String]?,
        prompt: String
    ) -> [WatcherAlert] {
        var alerts: [WatcherAlert] = []
        let previousDigest = previousState?["lastBodyDigest"]

        // Strategy 1: Content changed since last check
        if let current = currentBody, let previousDigest, currentDigest != previousDigest {
            alerts.append(WatcherAlert(
                id: UUID().uuidString,
                watcherId: config.id,
                watcherType: "custom",
                watcherName: config.name,
                priority: .medium,
                title: "🔄 \(config.name): Content changed",
                summary: "The monitored content has been updated.\n\nPrompt: \(prompt)\n\nSnippet: \(String(current.prefix(200)))...",
                sourceUrl: config.settings["url"],
                suggestedActions: ["Review changes", "Open URL"],
                timestamp: Date(),
                dedupeKey: "custom-change:\(config.id):\(currentDigest)"
            ))
        }

        // Strategy 2: Keyword matching
        let keywords = config.settings["keywords"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        if let body = currentBody, !keywords.isEmpty {
            let bodyLower = body.lowercased()
            let matched = keywords.filter { bodyLower.contains($0.lowercased()) }

            if !matched.isEmpty {
                alerts.append(WatcherAlert(
                    id: UUID().uuidString,
                    watcherId: config.id,
                    watcherType: "custom",
                    watcherName: config.name,
                    priority: .high,
                    title: "🎯 \(config.name): Keywords matched",
                    summary: "Found: \(matched.joined(separator: ", "))\n\nContext: \(String(body.prefix(300)))...",
                    sourceUrl: config.settings["url"],
                    suggestedActions: ["Review match", "Open URL"],
                    timestamp: Date(),
                    dedupeKey: "custom-keyword:\(config.id):\(stableDigest(matched.sorted().joined(separator: ",") + "|" + String(body.prefix(500))))"
                ))
            }
        }

        // Strategy 3: Prompt-only watcher (no URL). Periodic nudge.
        if config.settings["url"] == nil {
            let interval = max(config.intervalSeconds, 1)
            alerts.append(WatcherAlert(
                id: UUID().uuidString,
                watcherId: config.id,
                watcherType: "custom",
                watcherName: config.name,
                priority: .info,
                title: "📋 \(config.name): Scheduled check",
                summary: prompt,
                suggestedActions: ["Investigate", "Snooze"],
                timestamp: Date(),
                dedupeKey: "custom-prompt:\(config.id):\(Int(Date().timeIntervalSince1970) / interval)"
            ))
        }

        return alerts
    }

    private func stableDigest(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    private func errorBucketKey(for config: Watcher) -> Int {
        let interval = max(config.intervalSeconds, 60)
        let bucketSize = max(interval * 3, 300)
        return Int(Date().timeIntervalSince1970) / bucketSize
    }
}
