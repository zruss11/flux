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
struct WatcherCheckResult {
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
    private var states: [String: [String: String]] = [:]
    private var seenDedupeKeys: [String: Set<String>] = [:]
    private var dedupeOrder: [String: [String]] = [:]
    private var runningChecks: Set<String> = []

    /// Maximum number of dedup keys to retain per watcher.
    private let maxDedupHistory = 500

    private init() {}

    // MARK: - Provider Registration

    func registerProvider(_ provider: WatcherProvider) {
        providers[provider.type] = provider
        Log.app.info("WatcherEngine: registered provider for type \(provider.type.rawValue)")
    }

    // MARK: - Watcher Lifecycle

    func startWatcher(_ watcher: Watcher, credentials: [String: String] = [:]) {
        stopWatcher(id: watcher.id)

        var normalized = watcher
        normalized.intervalSeconds = Watcher.clampIntervalSeconds(normalized.intervalSeconds)

        guard normalized.enabled else { return }
        guard providers[normalized.type] != nil else {
            Log.app.error("WatcherEngine: no provider for type \(normalized.type.rawValue)")
            return
        }

        // Run an initial check immediately.
        Task { await runCheck(watcher: normalized, credentials: credentials) }

        // Schedule recurring checks.
        let interval = TimeInterval(normalized.intervalSeconds)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.runningChecks.contains(normalized.id) else { return }
                await self.runCheck(watcher: normalized, credentials: credentials)
            }
        }
        timers[normalized.id] = timer

        Log.app.info("WatcherEngine: started \(normalized.name) (every \(normalized.intervalSeconds)s)")
    }

    func stopWatcher(id: String) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        runningChecks.remove(id)
        states.removeValue(forKey: id)
        seenDedupeKeys.removeValue(forKey: id)
        dedupeOrder.removeValue(forKey: id)
    }

    func stopAll() {
        for (_, timer) in timers {
            timer.invalidate()
        }
        timers.removeAll()
        runningChecks.removeAll()
        states.removeAll()
        seenDedupeKeys.removeAll()
        dedupeOrder.removeAll()
        Log.app.info("WatcherEngine: all watchers stopped")
    }

    // MARK: - Check Execution

    private func runCheck(watcher: Watcher, credentials: [String: String]) async {
        guard !runningChecks.contains(watcher.id) else { return }
        runningChecks.insert(watcher.id)
        defer { runningChecks.remove(watcher.id) }

        guard let provider = providers[watcher.type] else { return }

        let previousState = states[watcher.id]

        do {
            let result = try await provider.check(
                config: watcher,
                credentials: credentials,
                previousState: previousState
            )

            // Suppress late results if the watcher was stopped during the check.
            guard timers[watcher.id] != nil else {
                Log.app.info("WatcherEngine: \(watcher.name) was stopped during check — discarding results")
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

    private func isDuplicate(dedupeKey: String, watcherId: String) -> Bool {
        seenDedupeKeys[watcherId]?.contains(dedupeKey) == true
    }

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
