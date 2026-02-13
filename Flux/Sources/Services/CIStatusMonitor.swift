import Foundation
import os

/// Aggregate CI health across all watched GitHub repos.
enum CIAggregateStatus: Equatable, Sendable {
    /// No repos configured — hide the indicator.
    case idle
    /// All latest workflow runs succeeded.
    case passing
    /// At least one latest run failed.
    case failing
    /// At least one run is currently in progress.
    case running
    /// Cannot reach `gh` CLI or no data yet.
    case unknown
}

/// Lightweight monitor that polls `gh run list` to maintain a live aggregate
/// CI status for the notch indicator. Uses adaptive polling independent of the
/// 5-minute `WatcherEngine` alert cycle.
///
/// When a repo transitions status (e.g. running → passing) the monitor uses
/// Apple Foundation Models to craft a one-line ticker message, then pushes it
/// to `IslandWindowManager` for display below the island.
@MainActor
@Observable
final class CIStatusMonitor {
    static let shared = CIStatusMonitor()

    private(set) var aggregateStatus: CIAggregateStatus = .idle

    /// Per-repo aggregate conclusion for the latest commit's workflow runs.
    private(set) var repoStatuses: [String: CIAggregateStatus] = [:]

    private var timer: Timer?
    private var isRefreshing = false
    private var currentPollInterval: TimeInterval?
    private let steadyPollInterval: TimeInterval = 30
    private let activePollInterval: TimeInterval = 10

    /// Previous repo statuses used to detect transitions.
    private var previousRepoStatuses: [String: CIAggregateStatus] = [:]

    /// Per-repo latest run metadata for generating rich ticker messages.
    private var latestRunInfo: [String: CIRunInfo] = [:]

    private init() {}

    // MARK: - Run Info

    /// Lightweight metadata about the latest workflow run for ticker messages.
    struct CIRunInfo: Sendable {
        let workflowName: String
        let headBranch: String
        let conclusion: String
        let event: String      // "pull_request", "push", etc.
    }

    // MARK: - Lifecycle

    /// Start polling. Safe to call multiple times.
    func start() {
        stop()
        // Immediate first check.
        Task { await refresh() }
        scheduleTimer(interval: steadyPollInterval)
    }

    /// Stop the polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        currentPollInterval = nil
    }

    /// Force a single refresh (e.g. after adding a new repo).
    func forceRefresh() {
        Task { await refresh() }
    }

    // MARK: - Core Refresh

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let repos = watchedRepos()
        guard !repos.isEmpty else {
            aggregateStatus = .idle
            repoStatuses = [:]
            previousRepoStatuses = [:]
            latestRunInfo = [:]
            updatePollingCadence()
            return
        }

        var statuses: [String: CIAggregateStatus] = [:]
        var runInfos: [String: CIRunInfo] = [:]

        await withTaskGroup(of: (String, CIAggregateStatus, CIRunInfo?).self) { group in
            for repo in repos {
                group.addTask { [self] in
                    let (status, info) = await self.checkRepo(repo)
                    return (repo, status, info)
                }
            }

            for await (repo, status, info) in group {
                statuses[repo] = status
                if let info { runInfos[repo] = info }
            }
        }

        // Detect transitions and fire ticker notifications.
        let oldStatuses = previousRepoStatuses
        previousRepoStatuses = statuses
        latestRunInfo = runInfos
        repoStatuses = statuses
        aggregateStatus = aggregate(statuses)
        updatePollingCadence()

        // Only fire transitions when we had a valid previous state (not the first poll).
        if !oldStatuses.isEmpty {
            for (repo, newStatus) in statuses {
                let oldStatus = oldStatuses[repo] ?? .unknown
                if oldStatus != newStatus, shouldFireTicker(from: oldStatus, to: newStatus) {
                    await generateTickerMessage(repo: repo, from: oldStatus, to: newStatus, info: runInfos[repo])
                }
            }
        }
    }

    /// Returns true for transitions worth notifying about.
    private func shouldFireTicker(from old: CIAggregateStatus, to newSt: CIAggregateStatus) -> Bool {
        if newSt == .failing && old != .failing { return true } // any red
        if old == .running && newSt == .passing { return true } // all green
        if old == .failing && newSt == .passing { return true } // recovery
        return false
    }

    // MARK: - Per-Repo Check

    private func checkRepo(_ repo: String) async -> (CIAggregateStatus, CIRunInfo?) {
        do {
            let result = try await runGH([
                "run", "list",
                "--repo", repo,
                "--limit", "30",
                "--json", "conclusion,status,name,headBranch,event,headSha",
            ])

            Log.app.info("CIStatusMonitor: \(repo) exitCode=\(result.exitCode) output=\(result.output)")

            guard result.exitCode == 0 else {
                return (.unknown, nil)
            }

            guard let data = result.output.data(using: .utf8),
                  let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return (.unknown, nil)
            }

            // No workflow runs at all — repo has no CI, treat as neutral/passing.
            guard let latest = runs.first else {
                return (.passing, nil)
            }

            // Aggregate over all runs for the latest commit so "all green" only
            // fires when every workflow has finished successfully.
            let scopedRuns = runsForLatestCommit(allRuns: runs, latestRun: latest)
            let aggregateStatus = aggregateRuns(scopedRuns)

            let infoSource = scopedRuns.first ?? latest
            let status = (infoSource["status"] as? String ?? "").lowercased()
            let conclusion = (infoSource["conclusion"] as? String ?? "").lowercased()
            let info = CIRunInfo(
                workflowName: infoSource["name"] as? String ?? "CI",
                headBranch: infoSource["headBranch"] as? String ?? "",
                conclusion: conclusion.isEmpty ? status : conclusion,
                event: infoSource["event"] as? String ?? ""
            )

            return (aggregateStatus, info)
        } catch {
            Log.app.error("CIStatusMonitor: failed to check \(repo) — \(error.localizedDescription)")
            return (.unknown, nil)
        }
    }

    private func runsForLatestCommit(allRuns: [[String: Any]], latestRun: [String: Any]) -> [[String: Any]] {
        let latestSha = (latestRun["headSha"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !latestSha.isEmpty {
            let sameSha = allRuns.filter { run in
                (run["headSha"] as? String ?? "") == latestSha
            }
            if !sameSha.isEmpty { return sameSha }
        }

        // Fallback when `headSha` is unavailable.
        let latestBranch = latestRun["headBranch"] as? String ?? ""
        let latestEvent = latestRun["event"] as? String ?? ""
        return allRuns.filter { run in
            let branch = run["headBranch"] as? String ?? ""
            let event = run["event"] as? String ?? ""
            return branch == latestBranch && event == latestEvent
        }
    }

    private func aggregateRuns(_ runs: [[String: Any]]) -> CIAggregateStatus {
        guard !runs.isEmpty else { return .unknown }

        var statuses: [CIAggregateStatus] = []
        statuses.reserveCapacity(runs.count)
        for run in runs {
            statuses.append(statusForRun(run))
        }

        if statuses.contains(.failing) { return .failing } // any red
        if statuses.contains(.running) { return .running } // still in progress
        if statuses.contains(.unknown) { return .unknown }
        return .passing
    }

    private func statusForRun(_ run: [String: Any]) -> CIAggregateStatus {
        let status = (run["status"] as? String ?? "").lowercased()
        let conclusion = (run["conclusion"] as? String ?? "").lowercased()

        if ["in_progress", "queued", "waiting", "requested", "pending"].contains(status) {
            return .running
        }

        if ["failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"].contains(conclusion) {
            return .failing
        }

        if ["success", "neutral", "skipped"].contains(conclusion) {
            return .passing
        }

        return .unknown
    }

    // MARK: - Ticker Message Generation

    private func generateTickerMessage(repo: String, from oldStatus: CIAggregateStatus, to newStatus: CIAggregateStatus, info: CIRunInfo?) async {
        let shortRepo = repo.components(separatedBy: "/").last ?? repo
        let branchPart = info?.headBranch ?? ""
        let workflowPart = info?.workflowName ?? "CI"

        // Try Foundation Models first for a polished one-liner.
        let message: String
        if FoundationModelsClient.shared.isAvailable {
            let systemPrompt = """
            You write ultra-short, punchy one-liner status updates for a developer dashboard ticker.
            Keep it under 60 characters. Use one emoji. No hashtags. No quotes.
            """
            let userPrompt: String
            switch newStatus {
            case .passing:
                userPrompt = "Repo '\(shortRepo)' branch '\(branchPart)' just went all green (all checks passed). Celebrate briefly."
            case .failing:
                userPrompt = "Repo '\(shortRepo)' branch '\(branchPart)' has at least one failed check. Report it tersely."
            default:
                userPrompt = "The workflow '\(workflowPart)' on repo '\(shortRepo)' branch '\(branchPart)' changed status to \(newStatus). Report it tersely."
            }

            do {
                let generated = try await FoundationModelsClient.shared.completeText(system: systemPrompt, user: userPrompt)
                let cleaned = generated.trimmingCharacters(in: .whitespacesAndNewlines)
                message = cleaned.isEmpty ? fallbackMessage(repo: shortRepo, to: newStatus, workflow: workflowPart, branch: branchPart) : cleaned
            } catch {
                Log.app.info("CIStatusMonitor: Foundation Models unavailable, using fallback — \(error.localizedDescription)")
                message = fallbackMessage(repo: shortRepo, to: newStatus, workflow: workflowPart, branch: branchPart)
            }
        } else {
            message = fallbackMessage(repo: shortRepo, to: newStatus, workflow: workflowPart, branch: branchPart)
        }

        Log.app.info("CIStatusMonitor: ticker → \(message)")
        IslandWindowManager.shared.showTickerNotification(message)
    }

    private func fallbackMessage(repo: String, to status: CIAggregateStatus, workflow: String, branch: String) -> String {
        let branchLabel = branch.isEmpty ? "" : " (\(branch))"
        switch status {
        case .passing:
            return "✅ \(repo)\(branchLabel) — all checks passed"
        case .failing:
            return "❌ \(repo)\(branchLabel) — check failed"
        default:
            return "🔄 \(repo)\(branchLabel) — \(workflow) status changed"
        }
    }

    // MARK: - Aggregation

    /// Priority: failing > running > unknown > passing.
    private func aggregate(_ statuses: [String: CIAggregateStatus]) -> CIAggregateStatus {
        guard !statuses.isEmpty else { return .idle }

        let values = Array(statuses.values)

        if values.contains(.failing) { return .failing }
        if values.contains(.running) { return .running }
        if values.contains(.unknown) { return .unknown }
        return .passing
    }

    private func updatePollingCadence() {
        let hasRunningRepo = repoStatuses.values.contains(.running)
        let desired = hasRunningRepo ? activePollInterval : steadyPollInterval
        guard currentPollInterval != desired else { return }
        scheduleTimer(interval: desired)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        currentPollInterval = interval

        let nextTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        timer = nextTimer

        // Keep polling during UI tracking/menu run loop modes.
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    // MARK: - Helpers

    private func watchedRepos() -> [String] {
        let raw = UserDefaults.standard.string(forKey: "githubWatchedRepos") ?? ""
        return raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - gh CLI Runner

    private struct GHResult: Sendable {
        let output: String
        let exitCode: Int32
    }

    private func runGH(_ arguments: [String]) async throws -> GHResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

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
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: GHResult(output: output, exitCode: process.terminationStatus))
            }
        }
    }
}
