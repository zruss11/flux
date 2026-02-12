import Foundation
import os

/// Protocol all watcher implementations conform to.
protocol WatcherProvider: Sendable {
    var type: Watcher.WatcherType { get }

    /// Perform a single check and return any new alerts.
    func check(
        config: Watcher,
        credentials: [String: String],
        previousState: [String: String]?
    ) async throws -> WatcherCheckResult
}

/// Result of a single watcher check.
struct WatcherCheckResult: Sendable {
    let alerts: [WatcherAlert]
    /// Optional state to persist between checks (e.g., last seen message ID).
    var nextState: [String: String]?
}

// MARK: - WatcherEngine

/// Native Swift engine for proactive monitoring.
///
/// Manages registered watcher providers, schedules periodic checks via `Timer`,
/// deduplicates alerts, and emits new alerts via a callback.
@MainActor
final class WatcherEngine {
    static let shared = WatcherEngine()

    /// Called when new alerts are detected.
    var onAlerts: (([WatcherAlert]) -> Void)?

    private var providers: [Watcher.WatcherType: WatcherProvider] = [:]
    private var timers: [String: Timer] = [:]
    private var watcherRunTokens: [String: UUID] = [:]
    private var states: [String: [String: String]] = [:]
    private var seenDedupeKeys: [String: Set<String>] = [:]
    private var dedupeOrder: [String: [String]] = [:]
    private var runningChecks: [String: UUID] = [:]

    /// Maximum number of dedup keys to retain per watcher.
    private let maxDedupHistory = 500

    private init() {}

    // MARK: - Provider Registration

    /// Registers a provider implementation for a watcher type.
    func registerProvider(_ provider: WatcherProvider) {
        providers[provider.type] = provider
        Log.app.info("WatcherEngine: registered provider for type \(provider.type.rawValue)")
    }

    // MARK: - Watcher Lifecycle

    /// Starts (or restarts) a watcher and schedules periodic checks.
    func startWatcher(_ watcher: Watcher, credentials: [String: String] = [:]) {
        stopWatcher(id: watcher.id)

        var normalized = watcher
        normalized.intervalSeconds = Watcher.clampIntervalSeconds(normalized.intervalSeconds)

        guard normalized.enabled else { return }
        guard providers[normalized.type] != nil else {
            Log.app.error("WatcherEngine: no provider for type \(normalized.type.rawValue)")
            return
        }

        let runToken = UUID()
        watcherRunTokens[normalized.id] = runToken

        // Run an initial check immediately.
        Task { await runCheck(watcher: normalized, credentials: credentials, runToken: runToken) }

        // Schedule recurring checks.
        let interval = TimeInterval(normalized.intervalSeconds)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.runningChecks[normalized.id] == nil else { return }
                await self.runCheck(watcher: normalized, credentials: credentials, runToken: runToken)
            }
        }
        timers[normalized.id] = timer

        Log.app.info("WatcherEngine: started \(normalized.name) (every \(normalized.intervalSeconds)s)")
    }

    /// Stops a watcher and clears all in-memory state for that watcher.
    func stopWatcher(id: String) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        watcherRunTokens.removeValue(forKey: id)
        runningChecks.removeValue(forKey: id)
        states.removeValue(forKey: id)
        seenDedupeKeys.removeValue(forKey: id)
        dedupeOrder.removeValue(forKey: id)
    }

    /// Stops all watchers and resets engine state.
    func stopAll() {
        for (_, timer) in timers {
            timer.invalidate()
        }
        timers.removeAll()
        watcherRunTokens.removeAll()
        runningChecks.removeAll()
        states.removeAll()
        seenDedupeKeys.removeAll()
        dedupeOrder.removeAll()
        Log.app.info("WatcherEngine: all watchers stopped")
    }

    // MARK: - Check Execution

    /// Executes one provider check, persists state, deduplicates, and emits alerts.
    private func runCheck(watcher: Watcher, credentials: [String: String], runToken: UUID? = nil) async {
        if let runToken, watcherRunTokens[watcher.id] != runToken {
            return
        }

        guard runningChecks[watcher.id] == nil else { return }
        let checkToken = UUID()
        runningChecks[watcher.id] = checkToken
        defer {
            if runningChecks[watcher.id] == checkToken {
                runningChecks.removeValue(forKey: watcher.id)
            }
        }

        guard let provider = providers[watcher.type] else { return }

        let previousState = states[watcher.id]

        do {
            let result = try await provider.check(
                config: watcher,
                credentials: credentials,
                previousState: previousState
            )

            if let runToken, watcherRunTokens[watcher.id] != runToken {
                Log.app.info("WatcherEngine: dropping stale result for \(watcher.name)")
                return
            }

            // Persist state.
            if let nextState = result.nextState {
                states[watcher.id] = nextState
            }

            // Deduplicate.
            let newAlerts = result.alerts.filter { alert in
                guard !isDuplicate(dedupeKey: alert.dedupeKey, watcherId: watcher.id) else { return false }
                remember(dedupeKey: alert.dedupeKey, watcherId: watcher.id)
                return true
            }

            if !newAlerts.isEmpty {
                Log.app.info("WatcherEngine: \(watcher.name) found \(newAlerts.count) new alert(s)")
                onAlerts?(newAlerts)
            }
        } catch {
            Log.app.error("WatcherEngine: \(watcher.name) check failed — \(error.localizedDescription)")
        }
    }

    /// Manually trigger a single check (useful for testing / "check now" button).
    func triggerCheck(watcher: Watcher, credentials: [String: String] = [:]) async {
        await runCheck(watcher: watcher, credentials: credentials)
    }

    // MARK: - Dedupe History

    /// Returns true when the dedupe key has already been seen for this watcher.
    private func isDuplicate(dedupeKey: String, watcherId: String) -> Bool {
        seenDedupeKeys[watcherId]?.contains(dedupeKey) == true
    }

    /// Stores a dedupe key and evicts oldest entries over the configured cap.
    private func remember(dedupeKey: String, watcherId: String) {
        var seen = seenDedupeKeys[watcherId] ?? Set<String>()
        var order = dedupeOrder[watcherId] ?? []
        guard !seen.contains(dedupeKey) else { return }

        seen.insert(dedupeKey)
        order.append(dedupeKey)

        while order.count > maxDedupHistory {
            let evicted = order.removeFirst()
            seen.remove(evicted)
        }

        seenDedupeKeys[watcherId] = seen
        dedupeOrder[watcherId] = order
    }
}
