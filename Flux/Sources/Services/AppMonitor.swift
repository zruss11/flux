import AppKit
import os

/// Monitors the frontmost application and emits updates when the active app changes.
///
/// Observes `NSWorkspace.didActivateApplicationNotification` and debounces rapid
/// app switches (200ms). On each change the `onActiveAppChanged` closure fires with
/// app name, bundle identifier, and PID.
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
    private var observer: NSObjectProtocol?
    private var lastActivationWasFlux = false

    private init() {}

    func start() {
        guard observer == nil else { return }
        Log.appMonitor.info("AppMonitor starting")

        // Capture initial state.
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            setActiveApp(from: frontmost)
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.scheduleUpdate(for: app)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        debounceItem?.cancel()
        debounceItem = nil
        Log.appMonitor.info("AppMonitor stopped")
    }

    // MARK: - Private

    private func scheduleUpdate(for app: NSRunningApplication) {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setActiveApp(from: app)
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func setActiveApp(from app: NSRunningApplication) {
        let appName = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? "unknown"
        let pid = app.processIdentifier

        let newApp = ActiveApp(appName: appName, bundleId: bundleId, pid: pid)

        // Ignore our own app activations — don't report Flux as the active app.
        if bundleId == Bundle.main.bundleIdentifier {
            lastActivationWasFlux = true
            return
        }

        // Skip if unchanged, unless we just activated Flux in between.
        if newApp == currentApp && !lastActivationWasFlux { return }
        lastActivationWasFlux = false

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
