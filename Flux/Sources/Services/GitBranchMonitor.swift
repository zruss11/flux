import Foundation
import os

/// Monitors the current git branch for the active workspace and provides
/// branch listing / checkout capabilities.
@MainActor
@Observable
final class GitBranchMonitor {
    static let shared = GitBranchMonitor()

    /// The current branch name (e.g. "main"). Nil when no workspace is set or
    /// the workspace isn't a git repo.
    private(set) var currentBranch: String?

    /// Available local branches, sorted by most recent commit first.
    private(set) var branches: [String] = []

    /// True while a checkout operation is in progress.
    private(set) var isCheckingOut = false

    private var timer: Timer?
    private var monitoredPath: String?
    private let pollInterval: TimeInterval = 5
    private var refreshGeneration: UInt64 = 0

    private init() {}

    // MARK: - Lifecycle

    /// Start monitoring the given workspace path. Safe to call repeatedly with
    /// different paths — the old timer is replaced.
    func monitor(workspacePath: String?) {
        stop()
        monitoredPath = workspacePath
        guard workspacePath != nil else {
            currentBranch = nil
            branches = []
            return
        }
        Task { await refresh() }
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        invalidateRefreshes()
    }

    /// Force an immediate refresh of the current branch.
    func forceRefresh() {
        Task { await refresh() }
    }

    // MARK: - Actions

    /// Fetch all local branches (cached in `branches`).
    func fetchBranches() async {
        guard let path = monitoredPath else {
            branches = []
            return
        }
        let result = await runGit(["branch", "--list", "--sort=-committerdate", "--format=%(refname:short)"], in: path)
        guard let output = result, !output.isEmpty else {
            branches = []
            return
        }
        branches = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Checkout a branch. Updates `currentBranch` on success.
    func checkout(_ branch: String) async -> Bool {
        guard let path = monitoredPath else { return false }
        isCheckingOut = true
        defer { isCheckingOut = false }

        let result = await runGit(["checkout", branch], in: path)
        if result != nil {
            invalidateRefreshes()
            currentBranch = branch
            return true
        }
        // Refresh to get the actual state even on failure.
        await refresh()
        return false
    }

    // MARK: - Internal

    private func refresh() async {
        guard let path = monitoredPath else {
            currentBranch = nil
            return
        }
        let generation = nextRefreshGeneration()
        let result = await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        guard generation == refreshGeneration, path == monitoredPath else { return }
        currentBranch = result?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextRefreshGeneration() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    private func invalidateRefreshes() {
        refreshGeneration &+= 1
    }

    // MARK: - Git CLI Runner

    private func runGit(_ arguments: [String], in directory: String) async -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        return await withCheckedContinuation { continuation in
            do {
                try process.run()
            } catch {
                Log.app.error("GitBranchMonitor: failed to launch git — \(error.localizedDescription)")
                continuation.resume(returning: nil)
                return
            }

            DispatchQueue.global(qos: .utility).async {
                // Drain stdout before waiting for exit to avoid a potential pipe
                // backpressure deadlock on larger git outputs.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }
        }
    }
}
