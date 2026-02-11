import Foundation
import AppKit

enum SkillPermission: String, Hashable, CaseIterable {
    case automation
    case accessibility
    case screenRecording
    case microphone
    case reminders

    var displayName: String {
        switch self {
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .microphone: return "Microphone"
        case .reminders: return "Reminders"
        }
    }

    var description: String {
        switch self {
        case .automation: return "Control other apps via AppleScript"
        case .accessibility: return "Read window contents and UI elements"
        case .screenRecording: return "Capture screenshots for context"
        case .microphone: return "Voice input for hands-free commands"
        case .reminders: return "Access Apple Reminders data"
        }
    }

    var icon: String {
        switch self {
        case .automation: return "gearshape.2.fill"
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.inset.filled.and.person.filled"
        case .microphone: return "mic.fill"
        case .reminders: return "checklist"
        }
    }

    private var systemSettingsCandidates: [String] {
        switch self {
        case .automation:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        case .accessibility:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        case .screenRecording:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        case .microphone:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        case .reminders:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
                "x-apple.systempreferences:com.apple.preference.security?Privacy",
            ]
        }
    }

    func openSystemSettings() {
        for str in systemSettingsCandidates {
            if let url = URL(string: str), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
