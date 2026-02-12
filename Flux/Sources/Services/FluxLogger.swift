import Foundation
import os

/// Centralized loggers for the Flux app using Apple's `os.Logger`.
///
/// Usage:
///   Log.bridge.info("Connected to sidecar")
///   Log.voice.error("Engine start failed: \(error)")
///   Log.skills.debug("Checking \(path)")   // debug messages are not persisted
///
/// View logs in Console.app with subsystem filter: `com.flux.app`
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.flux.app"

    /// App lifecycle, startup, delegate events
    static let app = Logger(subsystem: subsystem, category: "app")

    /// WebSocket bridge to Node sidecar
    static let bridge = Logger(subsystem: subsystem, category: "bridge")

    /// Screen capture via ScreenCaptureKit
    static let screen = Logger(subsystem: subsystem, category: "screen")

    /// Voice input, audio engine, transcription
    static let voice = Logger(subsystem: subsystem, category: "voice")

    /// Skill loading, installation, permissions
    static let skills = Logger(subsystem: subsystem, category: "skills")

    /// Accessibility reader (AXUIElement)
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")

    /// Tool execution (shortcuts, AppleScript, shell)
    static let tools = Logger(subsystem: subsystem, category: "tools")

    /// Automation service (scheduled tasks)
    static let automation = Logger(subsystem: subsystem, category: "automation")

    /// Active app monitoring (frontmost app changes)
    static let appMonitor = Logger(subsystem: subsystem, category: "appMonitor")

    /// Context manager (screen context aggregation)
    static let context = Logger(subsystem: subsystem, category: "context")

    /// Keychain and secret management
    static let keychain = Logger(subsystem: subsystem, category: "keychain")

    /// UI-layer diagnostics
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
