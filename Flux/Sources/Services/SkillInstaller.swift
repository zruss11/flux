import Foundation

enum SkillInstaller {
    enum InstallError: Error {
        case catalogEntryNotFound
        case directoryCreationFailed(Error)
        case fileWriteFailed(Error)
    }

    static func install(directoryName: String) async throws {
        guard let entry = SkillCatalog.recommended.first(where: { $0.directoryName == directoryName }) else {
            throw InstallError.catalogEntryNotFound
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let skillsDir = home.appendingPathComponent(".claude/skills")
        let skillDir = skillsDir.appendingPathComponent(entry.directoryName)

        let fm = FileManager.default

        do {
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        } catch {
            throw InstallError.directoryCreationFailed(error)
        }

        let skillMdPath = skillDir.appendingPathComponent("SKILL.md")
        do {
            try entry.skillMdContent.write(to: skillMdPath, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.fileWriteFailed(error)
        }

        print("[SkillInstaller] Installed skill '\(entry.displayName)' at \(skillDir.path)")
    }
}
