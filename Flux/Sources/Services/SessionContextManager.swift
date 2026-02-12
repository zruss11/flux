import AppKit
@preconcurrency import ApplicationServices
import Foundation

@Observable
@MainActor
final class SessionContextManager {

    static let shared = SessionContextManager()

    let historyStore = SessionHistoryStore()

    private(set) var currentAppName: String?
    private(set) var currentBundleId: String?
    private(set) var currentWindowTitle: String?
    private(set) var currentPid: Int32?
    private var currentSessionStart: Date?

    private var workspaceObserver: NSObjectProtocol?
    private var windowPollTimer: Timer?

    private let fluxBundleId = Bundle.main.bundleIdentifier ?? "com.flux.app"

    private init() {}

    func start() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self.handleAppActivation(app)
            }
        }

        // Poll for window title changes within the same app every 5 seconds
        windowPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollWindowTitle()
            }
        }
    }

    func stop() {
        // Complete current session before stopping
        completeCurrentSession()

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        windowPollTimer?.invalidate()
        windowPollTimer = nil
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        let appName = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier

        // Skip Flux itself
        guard bundleId != fluxBundleId else { return }

        // Complete previous session
        completeCurrentSession()

        // Read window title via lightweight AX call
        let pid = app.processIdentifier
        let windowTitle = readWindowTitle(pid: pid)

        currentAppName = appName
        currentBundleId = bundleId
        currentWindowTitle = windowTitle
        currentPid = pid
        currentSessionStart = Date()
    }

    private func pollWindowTitle() {
        guard let pid = currentPid else { return }
        let newTitle = readWindowTitle(pid: pid)
        if newTitle != currentWindowTitle, let newTitle {
            currentWindowTitle = newTitle
        }
    }

    private func completeCurrentSession() {
        guard let appName = currentAppName, let startedAt = currentSessionStart else { return }

        var session = AppSession(
            appName: appName,
            bundleId: currentBundleId,
            windowTitle: currentWindowTitle,
            startedAt: startedAt,
            endedAt: Date()
        )

        historyStore.record(session)

        currentAppName = nil
        currentBundleId = nil
        currentWindowTitle = nil
        currentPid = nil
        currentSessionStart = nil
    }

    /// Lightweight window title read — reads only kAXTitleAttribute from the focused window.
    private func readWindowTitle(pid: Int32) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard result == .success, let window = focusedWindow else { return nil }
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(
            // swiftlint:disable:next force_cast
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        )
        return title as? String
    }
}
