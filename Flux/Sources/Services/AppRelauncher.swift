import AppKit

enum AppRelauncher {
    static func relaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
