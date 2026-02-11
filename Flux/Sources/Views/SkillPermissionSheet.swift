import SwiftUI
@preconcurrency import ApplicationServices
import AVFoundation

struct SkillPermissionSheet: View {
    let skill: Skill
    var onDismiss: () -> Void

    @State private var grantedPermissions: Set<SkillPermission> = []
    @State private var grantingPermission: SkillPermission?

    private var allGranted: Bool {
        skill.requiredPermissions.allSatisfy { grantedPermissions.contains($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: skill.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(skill.color)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(skill.color.opacity(0.15)))

                Text("\(skill.name) needs permissions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                Text("Grant access so this skill works correctly")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Permission rows
            VStack(spacing: 6) {
                ForEach(Array(skill.requiredPermissions).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { permission in
                    permissionRow(permission)
                }
            }

            // Action button
            Button {
                onDismiss()
            } label: {
                Text(allGranted ? "Done" : "Skip for Now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(allGranted ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(allGranted ? skill.color.opacity(0.3) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .task {
            while !Task.isCancelled {
                await MainActor.run { refreshPermissions() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func permissionRow(_ permission: SkillPermission) -> some View {
        let isGranted = grantedPermissions.contains(permission)

        return HStack(spacing: 10) {
            Image(systemName: permission.icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(permission.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green.opacity(0.8))
            } else {
                Button {
                    grantPermission(permission)
                } label: {
                    Text("Grant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func grantPermission(_ permission: SkillPermission) {
        grantingPermission = permission

        switch permission {
        case .automation:
            if let appName = SkillPermissionChecker.automationTargetApp(for: skill.directoryName) {
                SkillPermissionChecker.triggerAutomationPrompt(for: appName)
            }
            permission.openSystemSettings()

        case .accessibility:
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            permission.openSystemSettings()

        case .screenRecording:
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            permission.openSystemSettings()

        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    private func refreshPermissions() {
        for permission in skill.requiredPermissions {
            if SkillPermissionChecker.isGranted(permission) {
                grantedPermissions.insert(permission)
            }
        }
    }
}
