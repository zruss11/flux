import Foundation
import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import EventKit

enum SkillPermissionChecker {

    static func isGranted(_ permission: SkillPermission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .automation:
            // Per-app Automation status is not queryable; conservatively return false
            // so the user is always offered the chance to grant it.
            return false
        case .reminders:
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return status == .fullAccess
        }
    }

    /// Executes a harmless AppleScript targeting `appName`, which triggers the native
    /// "Flux wants to control <App>" macOS permission dialog.
    /// Runs on a background thread to avoid blocking the UI.
    static func triggerAutomationPrompt(for appName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"\(appName)\" to get name"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Maps skill directory names to the macOS application name targeted by Automation.
    static func automationTargetApp(for directoryName: String) -> String? {
        switch directoryName {
        case "apple-notes": return "Notes"
        case "imessage": return "Messages"
        case "calendar": return "Calendar"
        case "reminders": return "Reminders"
        case "spotify": return "Spotify"
        case "arc-browser": return "Arc"
        case "raycast": return "Raycast"
        default: return nil
        }
    }
}
