import AppKit
import Observation
import os

/// Monitors the frontmost application and emits updates when the active app changes.
///
/// Observes `NSWorkspace.didActivateApplicationNotification` and debounces rapid
/// app switches (200ms). On each change the `onActiveAppChanged` closure fires with
/// app name, bundle identifier, and PID.
@Observable
@MainActor
final class AppMonitor {
    static let shared = AppMonitor()

    struct ActiveApp: Codable, Sendable, Equatable {
        let appName: String
        let bundleId: String
        let pid: Int32
    }

    /// Current active app — updated automatically when the frontmost app changes.
    private(set) var currentApp: ActiveApp?

    /// Recent app history (newest first), capped at `maxHistory` entries.
    private(set) var recentApps: [ActiveApp] = []

    /// Called on the main actor when the active app changes.
    var onActiveAppChanged: ((ActiveApp) -> Void)?

    private let maxHistory = 10
    private var debounceItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.2
    private var isObserving = false

    private init() {}

    func start() {
        guard !isObserving else { return }
        Log.appMonitor.info("AppMonitor starting")

        // Capture initial state.
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            setActiveApp(from: frontmost)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = true
    }

    func stop() {
        if isObserving {
            NSWorkspace.shared.notificationCenter.removeObserver(
                self,
                name: NSWorkspace.didActivateApplicationNotification,
                object: nil
            )
        }
        isObserving = false
        debounceItem?.cancel()
        debounceItem = nil
        Log.appMonitor.info("AppMonitor stopped")
    }

    // MARK: - Private

    @objc
    private func handleApplicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        scheduleUpdate(for: app)
    }

    private func scheduleUpdate(for app: NSRunningApplication) {
        if isFluxApp(app) {
            clearActiveAppForFlux()
            return
        }
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setActiveApp(from: app)
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func isFluxApp(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func clearActiveAppForFlux() {
        debounceItem?.cancel()
        debounceItem = nil
        if currentApp != nil {
            Log.appMonitor.info("Flux activated; clearing active app state")
        }
        currentApp = nil
    }

    private func setActiveApp(from app: NSRunningApplication) {
        let appName = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? "unknown"
        let pid = app.processIdentifier

        let newApp = ActiveApp(appName: appName, bundleId: bundleId, pid: pid)

        // Clear tracked app when Flux activates so that returning to the same
        // app (A → Flux → A) always re-fires the callback with fresh data.
        if bundleId == Bundle.main.bundleIdentifier {
            clearActiveAppForFlux()
            return
        }

        // Skip if unchanged.
        if newApp == currentApp { return }

        currentApp = newApp

        // Maintain history (newest first, no consecutive duplicates).
        if recentApps.first != newApp {
            recentApps.insert(newApp, at: 0)
            if recentApps.count > maxHistory {
                recentApps.removeLast()
            }
        }

        Log.appMonitor.info("Active app changed: \(appName) (\(bundleId))")
        onActiveAppChanged?(newApp)
    }
}
