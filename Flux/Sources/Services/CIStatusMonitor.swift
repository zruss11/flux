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
@MainActor
@Observable
final class CIStatusMonitor {
    static let shared = CIStatusMonitor()

    private(set) var aggregateStatus: CIAggregateStatus = .idle

    /// Per-repo latest conclusion for more granular display in the future.
    private(set) var repoStatuses: [String: CIAggregateStatus] = [:]

    private var timer: Timer?
    private var isRefreshing = false
    private var currentPollInterval: TimeInterval?
    private let steadyPollInterval: TimeInterval = 30
    private let activePollInterval: TimeInterval = 10

    private init() {}

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
            updatePollingCadence(for: .idle)
            return
        }

        var statuses: [String: CIAggregateStatus] = [:]

        await withTaskGroup(of: (String, CIAggregateStatus).self) { group in
            for repo in repos {
                group.addTask { [self] in
                    let status = await self.checkRepo(repo)
                    return (repo, status)
                }
            }

            for await (repo, status) in group {
                statuses[repo] = status
            }
        }

        repoStatuses = statuses
        aggregateStatus = aggregate(statuses)
        updatePollingCadence(for: aggregateStatus)
    }

    // MARK: - Per-Repo Check

    private func checkRepo(_ repo: String) async -> CIAggregateStatus {
        do {
            let result = try await runGH([
                "run", "list",
                "--repo", repo,
                "--limit", "1",
                "--json", "conclusion,status",
            ])

            Log.app.info("CIStatusMonitor: \(repo) exitCode=\(result.exitCode) output=\(result.output)")

            guard result.exitCode == 0 else {
                return .unknown
            }

            guard let data = result.output.data(using: .utf8),
                  let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .unknown
            }

            // No workflow runs at all — repo has no CI, treat as neutral/passing
            guard let latest = runs.first else {
                return .passing
            }

            let status = latest["status"] as? String ?? ""
            let conclusion = latest["conclusion"] as? String ?? ""

            if status == "in_progress" || status == "queued" || status == "waiting" || status == "requested" || status == "pending" {
                return .running
            }

            switch conclusion {
            case "success":
                return .passing
            case "failure", "timed_out", "cancelled", "action_required":
                return .failing
            default:
                return .unknown
            }
        } catch {
            Log.app.error("CIStatusMonitor: failed to check \(repo) — \(error.localizedDescription)")
            return .unknown
        }
    }

    // MARK: - Aggregation

    /// Priority: running > failing > unknown > passing.
    private func aggregate(_ statuses: [String: CIAggregateStatus]) -> CIAggregateStatus {
        guard !statuses.isEmpty else { return .idle }

        let values = Array(statuses.values)

        if values.contains(.running) { return .running }
        if values.contains(.failing) { return .failing }
        if values.contains(.unknown) { return .unknown }
        return .passing
    }

    private func updatePollingCadence(for aggregateStatus: CIAggregateStatus) {
        let desired = aggregateStatus == .running ? activePollInterval : steadyPollInterval
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
