import AppKit
@preconcurrency import ApplicationServices
import Foundation

@Observable
@MainActor
final class SessionContextManager {

    static let shared = SessionContextManager()
    static let inAppContextTrackingEnabledKey = "inAppContextTrackingEnabled"

    let historyStore = SessionHistoryStore()

    private(set) var currentAppName: String?
    private(set) var currentBundleId: String?
    private(set) var currentWindowTitle: String?
    private(set) var currentContextSummary: String?
    private(set) var currentPid: Int32?
    private var currentSessionStart: Date?

    private var workspaceObserver: NSObjectProtocol?
    private var windowPollTimer: Timer?

    private let fluxBundleId = Bundle.main.bundleIdentifier ?? "com.flux.app"
    private static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox"
    ]
    private static let sensitiveBundleIds: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.lastpass.LastPass",
        "com.agilebits.onepassword7"
    ]

    private init() {}

    func start() {
        UserDefaults.standard.register(defaults: [
            Self.inAppContextTrackingEnabledKey: true
        ])

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
        historyStore.flush()

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

        // Complete previous session
        completeCurrentSession()

        // Skip Flux itself
        guard bundleId != fluxBundleId else { return }

        // Read window title via lightweight AX call
        let pid = app.processIdentifier
        let windowTitle = readWindowTitle(pid: pid)

        currentAppName = appName
        currentBundleId = bundleId
        currentWindowTitle = windowTitle
        currentPid = pid
        currentSessionStart = Date()
        refreshContextSummary(pid: pid)
    }

    private func pollWindowTitle() {
        guard let pid = currentPid else { return }
        let newTitle = readWindowTitle(pid: pid)
        if newTitle != currentWindowTitle, let newTitle {
            currentWindowTitle = newTitle
        }
        refreshContextSummary(pid: pid)
    }

    private func completeCurrentSession() {
        guard let appName = currentAppName, let startedAt = currentSessionStart else { return }
        let contextSummary = UserDefaults.standard.bool(forKey: Self.inAppContextTrackingEnabledKey)
            ? currentContextSummary
            : nil

        let session = AppSession(
            appName: appName,
            bundleId: currentBundleId,
            windowTitle: currentWindowTitle,
            startedAt: startedAt,
            endedAt: Date(),
            contextSummary: contextSummary
        )

        historyStore.record(session)

        currentAppName = nil
        currentBundleId = nil
        currentWindowTitle = nil
        currentContextSummary = nil
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

    private func refreshContextSummary(pid: Int32) {
        guard UserDefaults.standard.bool(forKey: Self.inAppContextTrackingEnabledKey) else {
            currentContextSummary = nil
            return
        }

        if let bundleId = currentBundleId, Self.sensitiveBundleIds.contains(bundleId) {
            currentContextSummary = nil
            return
        }

        currentContextSummary = readFocusedContextSummary(pid: pid)
    }

    private func readFocusedContextSummary(pid: Int32) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let focusedElement = readAXElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) else {
            return currentWindowTitle.map { "Window: \(sanitize($0, limit: 120))" }
        }

        let role = readAXStringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = readAXStringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        let title = readAXStringAttribute(kAXTitleAttribute as CFString, from: focusedElement)
        let description = readAXStringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement)
        let value = readAXStringAttribute(kAXValueAttribute as CFString, from: focusedElement)

        var parts: [String] = []
        if let currentWindowTitle, !currentWindowTitle.isEmpty {
            parts.append("Window: \(sanitize(currentWindowTitle, limit: 120))")
        }

        if let role {
            if let subrole, !subrole.isEmpty {
                parts.append("Focus: \(role) (\(subrole))")
            } else {
                parts.append("Focus: \(role)")
            }
        }

        if let title, !title.isEmpty {
            parts.append("Element: \(sanitize(title, limit: 100))")
        } else if let description, !description.isEmpty {
            parts.append("Element: \(sanitize(description, limit: 100))")
        }

        if let value, !value.isEmpty {
            if shouldRedactValue(role: role, subrole: subrole) {
                parts.append("Text length: \(value.count)")
            } else {
                parts.append("Value: \(sanitize(value, limit: 120))")
            }
        }

        let summary = parts.joined(separator: " | ")
        return summary.isEmpty ? nil : sanitize(summary, limit: 320)
    }

    private func shouldRedactValue(role: String?, subrole: String?) -> Bool {
        if subrole == "AXSecureTextField" {
            return true
        }
        guard let role else { return false }
        return Self.editableRoles.contains(role)
    }

    private func readAXElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return value as! AXUIElement
    }

    private func readAXStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }

        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let attributed = value as? NSAttributedString {
            let trimmed = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func sanitize(_ text: String, limit: Int) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count <= limit {
            return singleLine
        }
        return String(singleLine.prefix(limit - 1)) + "…"
    }
}
