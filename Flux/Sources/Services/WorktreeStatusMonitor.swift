import Foundation
import os

enum WorktreeLane: Int, CaseIterable, Sendable {
    case inReview = 0
    case inProgress = 1
    case done = 2

    var title: String {
        switch self {
        case .inReview: return "In review"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }
}

enum WorktreeCIStatus: Sendable, Equatable {
    case passing
    case failing
    case running
    case unknown
}

struct WorktreeDiffStat: Sendable {
    let additions: Int
    let deletions: Int

    var isZero: Bool {
        additions == 0 && deletions == 0
    }
}

struct WorktreeSnapshot: Identifiable, Sendable {
    let id: String
    let branch: String
    let path: String
    let lane: WorktreeLane
    let ciStatus: WorktreeCIStatus
    let prNumber: Int?
    let prURL: String?
    let mergeStateStatus: String?
    let diff: WorktreeDiffStat
    let aheadCount: Int
    let behindCount: Int
    let updatedAt: Date

    var prompt: String {
        if let prNumber {
            return "Give me a merge-readiness summary for PR #\(prNumber) on branch \(branch), including CI and remaining blockers."
        }

        return "Give me a status summary for worktree branch \(branch), including what changed (+\(diff.additions)/-\(diff.deletions)) and next steps."
    }
}

@MainActor
@Observable
final class WorktreeStatusMonitor {
    static let shared = WorktreeStatusMonitor()

    private(set) var snapshots: [WorktreeSnapshot] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private var monitoredPath: String?
    private var timer: Timer?
    private var refreshGeneration: UInt64 = 0

    private let pollInterval: TimeInterval = 45

    private init() {}

    func monitor(workspacePath: String?) {
        stop()
        monitoredPath = workspacePath

        guard workspacePath != nil else {
            snapshots = []
            lastError = nil
            return
        }

        Task {
            await refresh()
        }

        let nextTimer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        invalidateRefreshes()
    }

    func forceRefresh() {
        Task {
            await refresh()
        }
    }

    private func refresh() async {
        guard let path = monitoredPath else {
            snapshots = []
            lastError = nil
            return
        }

        let generation = nextRefreshGeneration()
        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        guard let worktreeOutput = await runGit(["worktree", "list", "--porcelain"], in: path)?.output else {
            guard generation == refreshGeneration else { return }
            snapshots = []
            lastError = "Unable to read git worktrees"
            return
        }

        let entries = parseWorktreeList(worktreeOutput)
        guard generation == refreshGeneration, path == monitoredPath else { return }

        guard !entries.isEmpty else {
            snapshots = []
            lastError = nil
            return
        }

        let repo = await resolveGitHubRepo(from: path)
        let baseRef = await resolveDefaultBaseRef(from: path)

        var prByBranch: [String: PullRequestInfo] = [:]
        var ciByBranch: [String: WorktreeCIStatus] = [:]

        if let repo, await hasGitHubAuth() {
            prByBranch = await fetchOpenPullRequests(repo: repo)
            ciByBranch = await fetchRecentBranchCIStatuses(repo: repo)
        }

        var enriched: [WorktreeSnapshot] = []
        enriched.reserveCapacity(entries.count)

        for entry in entries {
            if let snapshot = await buildSnapshot(
                for: entry,
                baseRef: baseRef,
                pullRequestsByBranch: prByBranch,
                ciByBranch: ciByBranch
            ) {
                enriched.append(snapshot)
            }
        }

        guard generation == refreshGeneration, path == monitoredPath else { return }

        snapshots = enriched.sorted { lhs, rhs in
            if lhs.lane.rawValue != rhs.lane.rawValue {
                return lhs.lane.rawValue < rhs.lane.rawValue
            }

            let lhsDelta = lhs.diff.additions + lhs.diff.deletions
            let rhsDelta = rhs.diff.additions + rhs.diff.deletions
            if lhsDelta != rhsDelta {
                return lhsDelta > rhsDelta
            }

            return lhs.branch.localizedCaseInsensitiveCompare(rhs.branch) == .orderedAscending
        }

        lastError = nil
    }

    private func buildSnapshot(
        for entry: WorktreeEntry,
        baseRef: String,
        pullRequestsByBranch: [String: PullRequestInfo],
        ciByBranch: [String: WorktreeCIStatus]
    ) async -> WorktreeSnapshot? {
        let diff = await diffStats(path: entry.path, baseRef: baseRef)
        let (behind, ahead) = await aheadBehind(path: entry.path, baseRef: baseRef)

        let pullRequest = pullRequestsByBranch[entry.branch]
        let prCIStatus = pullRequest.map(ciStatus(from:))
        let ciStatus = (prCIStatus == .unknown || prCIStatus == nil)
            ? (ciByBranch[entry.branch] ?? .unknown)
            : (prCIStatus ?? .unknown)

        let lane: WorktreeLane
        if pullRequest != nil {
            lane = .inReview
        } else if diff.isZero, ahead == 0, behind == 0 {
            lane = .done
        } else {
            lane = .inProgress
        }

        return WorktreeSnapshot(
            id: entry.path,
            branch: entry.branch,
            path: entry.path,
            lane: lane,
            ciStatus: ciStatus,
            prNumber: pullRequest?.number,
            prURL: pullRequest?.url,
            mergeStateStatus: pullRequest?.mergeStateStatus,
            diff: diff,
            aheadCount: ahead,
            behindCount: behind,
            updatedAt: Date()
        )
    }

    private func diffStats(path: String, baseRef: String) async -> WorktreeDiffStat {
        guard let output = await runGit(["diff", "--shortstat", "\(baseRef)...HEAD"], in: path)?.output else {
            return WorktreeDiffStat(additions: 0, deletions: 0)
        }

        let additions = extractFirstInt(from: output, pattern: #"(\d+)\s+insertion"#) ?? 0
        let deletions = extractFirstInt(from: output, pattern: #"(\d+)\s+deletion"#) ?? 0
        return WorktreeDiffStat(additions: additions, deletions: deletions)
    }

    private func aheadBehind(path: String, baseRef: String) async -> (behind: Int, ahead: Int) {
        guard let output = await runGit(["rev-list", "--left-right", "--count", "\(baseRef)...HEAD"], in: path)?.output else {
            return (0, 0)
        }

        let parts = output
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Int($0) }

        guard parts.count >= 2 else { return (0, 0) }
        return (parts[0], parts[1])
    }

    private func resolveDefaultBaseRef(from path: String) async -> String {
        if let remoteHead = await runGit(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: path)?.output,
           !remoteHead.isEmpty {
            return remoteHead
        }

        if let mainExists = await runGit(["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"], in: path),
           mainExists.exitCode == 0 {
            return "origin/main"
        }

        if let masterExists = await runGit(["show-ref", "--verify", "--quiet", "refs/remotes/origin/master"], in: path),
           masterExists.exitCode == 0 {
            return "origin/master"
        }

        return "origin/main"
    }

    private func hasGitHubAuth() async -> Bool {
        guard let result = await runGH(["auth", "status", "--active"]) else {
            return false
        }
        return result.exitCode == 0
    }

    private func fetchOpenPullRequests(repo: String) async -> [String: PullRequestInfo] {
        guard let result = await runGH([
            "pr", "list",
            "--repo", repo,
            "--state", "open",
            "--limit", "100",
            "--json", "number,headRefName,mergeStateStatus,isDraft,statusCheckRollup,url",
        ]), result.exitCode == 0,
        let data = result.output.data(using: .utf8),
        let prs = try? JSONDecoder().decode([PullRequestInfo].self, from: data) else {
            return [:]
        }

        var mapped: [String: PullRequestInfo] = [:]
        for pr in prs {
            if mapped[pr.headRefName] == nil {
                mapped[pr.headRefName] = pr
            }
        }
        return mapped
    }

    private func fetchRecentBranchCIStatuses(repo: String) async -> [String: WorktreeCIStatus] {
        guard let result = await runGH([
            "run", "list",
            "--repo", repo,
            "--limit", "100",
            "--json", "headBranch,status,conclusion",
        ]), result.exitCode == 0,
        let data = result.output.data(using: .utf8),
        let runs = try? JSONDecoder().decode([WorkflowRun].self, from: data) else {
            return [:]
        }

        var mapped: [String: WorktreeCIStatus] = [:]
        for run in runs {
            guard let headBranch = run.headBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !headBranch.isEmpty,
                  mapped[headBranch] == nil else {
                continue
            }

            mapped[headBranch] = ciStatus(status: run.status, conclusion: run.conclusion)
        }

        return mapped
    }

    private func ciStatus(from pr: PullRequestInfo) -> WorktreeCIStatus {
        guard let checks = pr.statusCheckRollup, !checks.isEmpty else {
            return .unknown
        }

        let states = checks.compactMap { check -> String? in
            if let state = check.state, !state.isEmpty { return state.uppercased() }
            if let status = check.status, !status.isEmpty { return status.uppercased() }
            if let conclusion = check.conclusion, !conclusion.isEmpty { return conclusion.uppercased() }
            return nil
        }

        if states.isEmpty { return .unknown }

        if states.contains(where: isFailingCheckState) {
            return .failing
        }

        if states.contains(where: isRunningCheckState) {
            return .running
        }

        if states.allSatisfy(isPassingCheckState) {
            return .passing
        }

        return .unknown
    }

    private func ciStatus(status: String?, conclusion: String?) -> WorktreeCIStatus {
        let normalizedStatus = (status ?? "").lowercased()
        let normalizedConclusion = (conclusion ?? "").lowercased()

        if ["in_progress", "queued", "waiting", "requested", "pending"].contains(normalizedStatus) {
            return .running
        }

        if ["failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"].contains(normalizedConclusion) {
            return .failing
        }

        if ["success", "neutral", "skipped"].contains(normalizedConclusion) {
            return .passing
        }

        return .unknown
    }

    private func isFailingCheckState(_ value: String) -> Bool {
        ["FAILURE", "FAILED", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"].contains(value)
    }

    private func isRunningCheckState(_ value: String) -> Bool {
        ["PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED", "WAITING", "REQUESTED"].contains(value)
    }

    private func isPassingCheckState(_ value: String) -> Bool {
        ["SUCCESS", "SUCCESSFUL", "NEUTRAL", "SKIPPED", "COMPLETED"].contains(value)
    }

    private func resolveGitHubRepo(from path: String) async -> String? {
        guard let origin = await runGit(["config", "--get", "remote.origin.url"], in: path)?.output,
              !origin.isEmpty else {
            return nil
        }

        return parseGitHubRepo(origin)
    }

    private func parseGitHubRepo(_ remoteURL: String) -> String? {
        guard let githubRange = remoteURL.range(of: "github.com") else {
            return nil
        }

        var tail = String(remoteURL[githubRange.upperBound...])
        tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        tail = tail.replacingOccurrences(of: ".git", with: "")

        let components = tail
            .split(separator: "/")
            .map(String.init)

        guard components.count >= 2 else {
            return nil
        }

        return "\(components[0])/\(components[1])"
    }

    private func parseWorktreeList(_ output: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let value = String(line)

            if value.hasPrefix("worktree ") {
                if let currentPath {
                    entries.append(WorktreeEntry(path: currentPath, branch: normalizeBranch(currentBranch, path: currentPath)))
                }

                currentPath = String(value.dropFirst("worktree ".count))
                currentBranch = nil
                continue
            }

            if value.hasPrefix("branch ") {
                let branchRef = String(value.dropFirst("branch ".count))
                currentBranch = branchRef.replacingOccurrences(of: "refs/heads/", with: "")
            }
        }

        if let currentPath {
            entries.append(WorktreeEntry(path: currentPath, branch: normalizeBranch(currentBranch, path: currentPath)))
        }

        return entries
    }

    private func normalizeBranch(_ branch: String?, path: String) -> String {
        let trimmed = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func extractFirstInt(from value: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: fullRange), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return Int(value[range])
    }

    private func nextRefreshGeneration() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    private func invalidateRefreshes() {
        refreshGeneration &+= 1
    }

    private struct WorktreeEntry: Sendable {
        let path: String
        let branch: String
    }

    private struct PullRequestInfo: Decodable, Sendable {
        let number: Int
        let headRefName: String
        let mergeStateStatus: String?
        let isDraft: Bool?
        let statusCheckRollup: [StatusCheck]?
        let url: String?
    }

    private struct StatusCheck: Decodable, Sendable {
        let state: String?
        let conclusion: String?
        let status: String?
    }

    private struct WorkflowRun: Decodable, Sendable {
        let headBranch: String?
        let status: String?
        let conclusion: String?
    }

    private struct CommandResult: Sendable {
        let output: String
        let exitCode: Int32
    }

    private func runGit(_ arguments: [String], in directory: String) async -> CommandResult? {
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
                Log.app.error("WorktreeStatusMonitor: failed to launch git — \(error.localizedDescription)")
                continuation.resume(returning: nil)
                return
            }

            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CommandResult(output: output, exitCode: process.terminationStatus))
            }
        }
    }

    private func runGH(_ arguments: [String]) async -> CommandResult? {
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

        return await withCheckedContinuation { continuation in
            do {
                try process.run()
            } catch {
                Log.app.error("WorktreeStatusMonitor: failed to launch gh — \(error.localizedDescription)")
                continuation.resume(returning: nil)
                return
            }

            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: CommandResult(output: output, exitCode: process.terminationStatus))
            }
        }
    }
}
