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
/// CI status for the notch indicator. Runs on a 60-second cadence, independent
/// of the 5-minute `WatcherEngine` alert cycle.
@MainActor
@Observable
final class CIStatusMonitor {
    static let shared = CIStatusMonitor()

    private(set) var aggregateStatus: CIAggregateStatus = .idle

    /// Per-repo latest conclusion for more granular display in the future.
    private(set) var repoStatuses: [String: CIAggregateStatus] = [:]

    private var timer: Timer?
    private let pollInterval: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    /// Start polling. Safe to call multiple times.
    func start() {
        stop()
        // Immediate first check.
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    /// Stop the polling timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force a single refresh (e.g. after adding a new repo).
    func forceRefresh() {
        Task { await refresh() }
    }

    // MARK: - Core Refresh

    private func refresh() async {
        let repos = watchedRepos()
        guard !repos.isEmpty else {
            aggregateStatus = .idle
            repoStatuses = [:]
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

            guard result.exitCode == 0, !result.output.isEmpty else {
                return .unknown
            }

            guard let data = result.output.data(using: .utf8),
                  let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let latest = runs.first else {
                return .unknown
            }

            let status = latest["status"] as? String ?? ""
            let conclusion = latest["conclusion"] as? String ?? ""

            if status == "in_progress" || status == "queued" || status == "waiting" {
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
