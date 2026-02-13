import SwiftUI
@preconcurrency import ScreenCaptureKit
@preconcurrency import ApplicationServices
import AVFoundation

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

    var shouldShowRestartHint: Bool {
        (didRequestAccessibility && !accessibilityGranted) ||
        (didRequestScreenRecording && !screenRecordingGranted)
    }

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.5), radius: 10)

                    Text("Welcome to Flux")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Flux needs a few permissions to be your AI copilot.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
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
                    Button {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        onComplete()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                Capsule()
                                    .fill(.white)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 8) {
                        Text("Grant all permissions above to continue")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        if shouldShowRestartHint {
                            Text("macOS may require restarting Flux after enabling permissions.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))

                            Button("Restart Flux") {
                                AppRelauncher.relaunch()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .padding(.top, 40)
            .frame(width: 500)
            .background {
                ZStack {
                    Color.black

                    // Subtle gradient for depth
                    LinearGradient(
                        colors: [.white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .task {
                while !Task.isCancelled {
                    checkPermissions()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                    .shadow(color: .green.opacity(0.3), radius: 5)
            } else {
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(FluxButtonStyle())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}
