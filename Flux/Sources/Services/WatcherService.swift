import Foundation
import os
import UserNotifications

/// Manages watchers and their alerts.
/// Persists configs, orchestrates the native WatcherEngine, routes alerts to
/// macOS notifications and/or chat.
@MainActor
@Observable
final class WatcherService {
    static let shared = WatcherService()

    private(set) var watchers: [Watcher] = []
    private(set) var alerts: [WatcherAlert] = []

    /// Callback invoked when a watcher alert should appear in chat.
    var onChatAlert: ((WatcherAlert) -> Void)?

    private let engine = WatcherEngine.shared

    private static let storageURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watchers.json")
    }()

    private static let alertsStorageURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watcher_alerts.json")
    }()

    private init() {
        loadWatchers()
        loadAlerts()
        requestNotificationPermission()
        registerProviders()

        // Wire up engine alert callback.
        engine.onAlerts = { [weak self] newAlerts in
            self?.handleIncomingAlerts(newAlerts)
        }
    }

    // MARK: - Setup

    /// Register all built-in watcher providers with the engine.
    private func registerProviders() {
        engine.registerProvider(EmailWatcherProvider())
        engine.registerProvider(GitHubWatcherProvider())
        engine.registerProvider(CustomWatcherProvider())
    }

    /// Start all enabled watchers. Call once after app launch.
    func startAll() {
        ensureDefaultGitHubWatcher()

        for watcher in watchers where watcher.enabled {
            let normalized = sanitizeWatcher(watcher)
            let creds = loadCredentialsFromKeychain(for: normalized)
            engine.startWatcher(normalized, credentials: creds)
        }
    }

    /// If no GitHub watcher exists yet, create one automatically.
    /// Uses `gh` CLI for auth so no credentials are needed.
    private func ensureDefaultGitHubWatcher() {
        let hasGitHub = watchers.contains { $0.type == .github }
        guard !hasGitHub else { return }

        let repos = UserDefaults.standard.string(forKey: "githubWatchedRepos") ?? ""
        Log.app.info("WatcherService: Auto-creating default GitHub watcher (gh CLI)")
        createWatcher(
            name: "GitHub",
            type: .github,
            intervalSeconds: 300,
            notificationMode: .both,
            settings: [
                "watchNotifications": "true",
                "watchCicd": "true",
                "repos": repos,
            ]
        )
    }

    /// Update the repos list for the GitHub watcher and restart it.
    func updateGitHubRepos(_ repos: String) {
        guard let index = watchers.firstIndex(where: { $0.type == .github }) else { return }
        var watcher = watchers[index]
        watcher.settings["repos"] = repos
        updateWatcher(watcher)
    }

    // MARK: - Watcher CRUD

    @discardableResult
    func createWatcher(
        name: String,
        type: Watcher.WatcherType,
        intervalSeconds: Int? = nil,
        notificationMode: Watcher.NotificationMode = .both,
        settings: [String: String] = [:],
        credentialKeys: [String] = []
    ) -> Watcher {
        let watcher = sanitizeWatcher(Watcher(
            name: name,
            type: type,
            intervalSeconds: intervalSeconds,
            notificationMode: notificationMode,
            settings: settings,
            credentialKeys: credentialKeys
        ))
        watchers.insert(watcher, at: 0)
        saveWatchers()

        if watcher.enabled {
            let creds = loadCredentialsFromKeychain(for: watcher)
            engine.startWatcher(watcher, credentials: creds)
        }

        return watcher
    }

    func updateWatcher(_ watcher: Watcher) {
        guard let index = watchers.firstIndex(where: { $0.id == watcher.id }) else { return }
        var updated = sanitizeWatcher(watcher)
        updated.updatedAt = Date()
        watchers[index] = updated
        saveWatchers()

        // Restart with new config.
        engine.stopWatcher(id: watcher.id)
        if updated.enabled {
            let creds = loadCredentialsFromKeychain(for: updated)
            engine.startWatcher(updated, credentials: creds)
        }
    }

    func deleteWatcher(id: String) {
        // Clean up keychain credentials before removal.
        if let watcher = watchers.first(where: { $0.id == id }) {
            for key in watcher.credentialKeys {
                Self.deleteCredential(watcherId: id, key: key)
            }
        }
        engine.stopWatcher(id: id)
        watchers.removeAll { $0.id == id }
        saveWatchers()
    }

    func toggleWatcher(id: String) {
        guard let index = watchers.firstIndex(where: { $0.id == id }) else { return }
        watchers[index].enabled.toggle()
        watchers[index] = sanitizeWatcher(watchers[index])
        watchers[index].updatedAt = Date()
        saveWatchers()

        let watcher = watchers[index]
        if watcher.enabled {
            let creds = loadCredentialsFromKeychain(for: watcher)
            engine.startWatcher(watcher, credentials: creds)
        } else {
            engine.stopWatcher(id: watcher.id)
        }
    }

    // MARK: - Alert Handling

    private func handleIncomingAlerts(_ newAlerts: [WatcherAlert]) {
        for alert in newAlerts {
            // Skip duplicates already in our local list.
            if alerts.contains(where: { $0.dedupeKey == alert.dedupeKey }) {
                continue
            }

            alerts.insert(alert, at: 0)

            // Route based on per-watcher notification mode.
            let watcher = watchers.first { $0.id == alert.watcherId }
            let mode = watcher?.notificationMode ?? .both

            switch mode {
            case .native:
                showNativeNotification(alert)
            case .chat:
                onChatAlert?(alert)
            case .both:
                showNativeNotification(alert)
                onChatAlert?(alert)
            case .silent:
                break
            }
        }

        // Trim alert history.
        if alerts.count > 200 {
            alerts = Array(alerts.prefix(200))
        }

        saveAlerts()
    }

    func dismissAlert(id: String) {
        guard let index = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[index].isDismissed = true
        saveAlerts()
    }

    func dismissAllAlerts() {
        for index in alerts.indices {
            alerts[index].isDismissed = true
        }
        saveAlerts()
    }

    var activeAlertCount: Int {
        alerts.filter { !$0.isDismissed }.count
    }

    // MARK: - Keychain Credentials

    private func loadCredentialsFromKeychain(for watcher: Watcher) -> [String: String] {
        var creds: [String: String] = [:]
        for key in watcher.credentialKeys {
            if let value = KeychainService.getString(forKey: "flux.watcher.\(watcher.id).\(key)") {
                creds[key] = value
            }
        }
        return creds
    }

    static func saveCredential(watcherId: String, key: String, value: String) {
        do {
            try KeychainService.setString(value, forKey: "flux.watcher.\(watcherId).\(key)")
        } catch {
            Log.app.error("WatcherService: failed to save credential \(key) for \(watcherId): \(error.localizedDescription)")
        }

        // Restart the watcher so it picks up the new credential.
        let service = WatcherService.shared
        if let watcher = service.watchers.first(where: { $0.id == watcherId }), watcher.enabled {
            let creds = service.loadCredentialsFromKeychain(for: watcher)
            service.engine.startWatcher(watcher, credentials: creds)
        }
    }

    static func deleteCredential(watcherId: String, key: String) {
        do {
            try KeychainService.deleteValue(forKey: "flux.watcher.\(watcherId).\(key)")
        } catch {
            Log.app.error("WatcherService: failed to delete credential \(key) for \(watcherId): \(error.localizedDescription)")
        }
    }

    // MARK: - Native Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Log.app.error("Notification permission error: \(error)")
            }
        }
    }

    private func showNativeNotification(_ alert: WatcherAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.summary
        content.sound = alert.priority <= .medium ? .default : nil

        if let url = alert.sourceUrl {
            content.userInfo["sourceUrl"] = url
        }

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Failed to deliver notification: \(error)")
            }
        }
    }

    // MARK: - Persistence

    private struct WatcherStore: Codable {
        let version: Int
        let watchers: [Watcher]
    }

    private func saveWatchers() {
        let store = WatcherStore(version: 1, watchers: watchers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(store)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            Log.app.error("WatcherService: failed to save watchers: \(error.localizedDescription)")
        }
    }

    private func loadWatchers() {
        guard let data = try? Data(contentsOf: Self.storageURL) else {
            watchers = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let store = try decoder.decode(WatcherStore.self, from: data)
            let normalized = store.watchers.map(sanitizeWatcher)
            let didNormalize = normalized != store.watchers
            watchers = normalized
            if didNormalize {
                saveWatchers()
            }
        } catch {
            Log.app.error("WatcherService: failed to decode watchers store: \(error.localizedDescription)")
            watchers = []
        }
    }

    private func saveAlerts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(alerts)
            try data.write(to: Self.alertsStorageURL, options: .atomic)
        } catch {
            Log.app.error("WatcherService: failed to save alerts: \(error.localizedDescription)")
        }
    }

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: Self.alertsStorageURL) else {
            alerts = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            alerts = try decoder.decode([WatcherAlert].self, from: data)
        } catch {
            Log.app.error("WatcherService: failed to decode alerts store: \(error.localizedDescription)")
            alerts = []
        }
    }

    private func sanitizeWatcher(_ watcher: Watcher) -> Watcher {
        var normalized = watcher
        normalized.intervalSeconds = Watcher.clampIntervalSeconds(normalized.intervalSeconds)
        let trimmedName = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.name = trimmedName.isEmpty ? normalized.type.displayName : trimmedName
        return normalized
    }
}
