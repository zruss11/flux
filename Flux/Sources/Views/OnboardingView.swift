import SwiftUI
@preconcurrency import ScreenCaptureKit
@preconcurrency import ApplicationServices
import Speech
import AVFoundation

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var microphoneGranted = false

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
                    }
                )

                PermissionRow(
                    title: "Screen Recording",
                    description: "Capture screenshots for context",
                    icon: "rectangle.inset.filled.and.person.filled",
                    isGranted: screenRecordingGranted,
                    onGrant: {
                        CGRequestScreenCaptureAccess()
                    }
                )

                PermissionRow(
                    title: "Microphone",
                    description: "Voice input for hands-free commands",
                    icon: "mic.fill",
                    isGranted: microphoneGranted,
                    onGrant: {
                        SFSpeechRecognizer.requestAuthorization { _ in }
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
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
                Text("Grant all permissions above to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(width: 500, height: 520)
        .task {
            while !Task.isCancelled {
                checkPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        microphoneGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
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
