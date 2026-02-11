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

        // Install into `.agents/skills` (the path the sidecar primarily scans) when a
        // project root is discoverable, otherwise fall back to `~/.claude/skills`.
        let skillsDir = resolveInstallDir()
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

    /// Prefer the project `.agents/skills` directory (which the sidecar scans first),
    /// falling back to `~/.claude/skills` when no project root is discoverable.
    private static func resolveInstallDir() -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        for key in ["FLUX_PROJECT_ROOT", "FLUX_REPO_ROOT", "SRCROOT", "PROJECT_DIR"] {
            if let p = env[key], !p.isEmpty {
                let dir = URL(fileURLWithPath: p, isDirectory: true)
                    .appendingPathComponent(".agents/skills")
                if fm.fileExists(atPath: dir.deletingLastPathComponent().path) {
                    return dir
                }
            }
        }

        // Walk upward from CWD looking for an existing `.agents` directory.
        var cur = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        var seen = Set<String>()
        while true {
            let path = cur.standardizedFileURL.path
            if seen.contains(path) { break }
            seen.insert(path)

            let agentsDir = cur.appendingPathComponent(".agents/skills")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: agentsDir.path, isDirectory: &isDir), isDir.boolValue {
                return agentsDir
            }
            let parent = cur.deletingLastPathComponent()
            if parent.path == cur.path { break }
            cur = parent
        }

        // Fallback: global Claude skills directory (also scanned by the sidecar).
        return fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
    }
}
