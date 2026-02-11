import SwiftUI
@preconcurrency import ScreenCaptureKit
@preconcurrency import ApplicationServices
import AVFoundation
import AppKit

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false
    @State private var didRequestAccessibility = UserDefaults.standard.bool(forKey: "didRequestAccessibility")
    @State private var didRequestScreenRecording = UserDefaults.standard.bool(forKey: "didRequestScreenRecording")

    var allPermissionsGranted: Bool {
        accessibilityGranted && screenRecordingGranted && microphoneGranted
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Welcome to Flux")
                    .font(.largeTitle.bold())

                Text("Flux needs a few permissions to be your AI copilot.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

#if DEBUG
                VStack(spacing: 4) {
                    Text("Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Path: \(Bundle.main.bundleURL.path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
#endif
            }

            VStack(spacing: 16) {
                PermissionRow(
                    title: "Accessibility",
                    description: "Read window contents and UI elements",
                    icon: "accessibility",
                    isGranted: accessibilityGranted,
                    onGrant: {
                        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
                        let options = [promptKey: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        didRequestAccessibility = true
                        UserDefaults.standard.set(true, forKey: "didRequestAccessibility")
                    }
                )

                PermissionRow(
                    title: "Screen Recording",
                    description: "Capture screenshots for context",
                    icon: "rectangle.inset.filled.and.person.filled",
                    isGranted: screenRecordingGranted,
                    onGrant: {
                        CGRequestScreenCaptureAccess()
                        didRequestScreenRecording = true
                        UserDefaults.standard.set(true, forKey: "didRequestScreenRecording")
                    }
                )

                PermissionRow(
                    title: "Microphone",
                    description: "Voice input for hands-free commands",
                    icon: "mic.fill",
                    isGranted: microphoneGranted,
                    onGrant: {
                        PermissionRequests.requestMicrophoneAccess { _ in }
                    }
                )
            }

            if allPermissionsGranted {
                Button("Get Started") {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(spacing: 8) {
                    Text("Grant all permissions above to continue")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if didRequestAccessibility && !accessibilityGranted {
                        Text("macOS may require restarting Flux after enabling Accessibility.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Restart Flux") {
                            relaunch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if didRequestScreenRecording && !screenRecordingGranted {
                        Text("macOS may require restarting Flux after enabling Screen Recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Restart Flux") {
                            relaunch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 520)
        .task {
            while !Task.isCancelled {
                await MainActor.run {
                    checkPermissions()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func relaunch() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            NSApp.terminate(nil)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
        }
    }
}
