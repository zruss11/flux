import AppKit
import os.log

enum AppRelauncher {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.flux", category: "AppRelauncher")

    static func relaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                logger.error("Failed to relaunch app: \(error.localizedDescription)")
                return
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
