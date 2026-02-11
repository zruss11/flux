import Foundation
import XCTest

@testable import Flux

final class SkillInstallerIntegrationTests: XCTestCase {
    func testInstallAndUninstallCustomSkill() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("flux-skill-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let originalProjectRoot = ProcessInfo.processInfo.environment["FLUX_PROJECT_ROOT"]
        setenv("FLUX_PROJECT_ROOT", tempDir.path, 1)
        let agentsRoot = tempDir.appendingPathComponent(".agents", isDirectory: true)
        try fm.createDirectory(at: agentsRoot, withIntermediateDirectories: true)

        let skillsRoot = agentsRoot.appendingPathComponent("skills", isDirectory: true)
        defer {
            if let originalProjectRoot {
                setenv("FLUX_PROJECT_ROOT", originalProjectRoot, 1)
            } else {
                unsetenv("FLUX_PROJECT_ROOT")
            }
            try? fm.removeItem(at: tempDir)
        }

        let skillId = "flux-test-\(UUID().uuidString)"
        try await SkillInstaller.installCustom(directoryName: skillId)

        let skillMd = skillsRoot.appendingPathComponent(skillId).appendingPathComponent("SKILL.md")
        XCTAssertTrue(fm.fileExists(atPath: skillMd.path))

        try await SkillInstaller.uninstall(directoryName: skillId)
        XCTAssertFalse(fm.fileExists(atPath: skillMd.path))
    }
}
