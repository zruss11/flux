import Foundation

enum SkillInstaller {
    enum InstallError: Error {
        case catalogEntryNotFound
        case directoryCreationFailed(Error)
        case fileWriteFailed(Error)
    }

    enum UninstallError: Error {
        case notFound
        case deletionFailed(Error)
    }

    enum CustomInstallError: Error {
        case invalidName
        case alreadyExists
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

    static func uninstall(directoryName: String) async throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Search all known skill directories
        var searchDirs: [URL] = []

        // Include project skills dir if discoverable
        let projectDir = resolveInstallDir()
        searchDirs.append(projectDir)

        searchDirs.append(contentsOf: [
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".agents/skills"),
        ])

        var removed = false
        for dir in searchDirs {
            let skillDir = dir.appendingPathComponent(directoryName)
            // Check for both regular directories and symlinks
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: skillDir.path, isDirectory: &isDir)
            // Also check if it's a symlink (fileExists follows symlinks, so check the link itself too)
            let isSymlink = (try? fm.attributesOfItem(atPath: skillDir.path)[.type] as? FileAttributeType) == .typeSymbolicLink

            if exists || isSymlink {
                do {
                    try fm.removeItem(at: skillDir)
                    removed = true
                    print("[SkillInstaller] Uninstalled skill '\(directoryName)' from \(skillDir.path)")
                } catch {
                    throw UninstallError.deletionFailed(error)
                }
            }
        }

        if !removed {
            throw UninstallError.notFound
        }
    }

    static func installCustom(directoryName: String) async throws {
        // Validate directory name: only alphanumeric, hyphens, underscores
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !directoryName.isEmpty,
              directoryName.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            throw CustomInstallError.invalidName
        }

        let skillsDir = resolveInstallDir()
        let skillDir = skillsDir.appendingPathComponent(directoryName)
        let fm = FileManager.default

        // Check if already exists
        if fm.fileExists(atPath: skillDir.path) {
            throw CustomInstallError.alreadyExists
        }

        do {
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        } catch {
            throw CustomInstallError.directoryCreationFailed(error)
        }

        // Create a display name from the directory name (capitalize, replace hyphens with spaces)
        let displayName = directoryName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let skillMdContent = """
        ---
        name: \(displayName)
        description: Custom skill
        ---
        # \(displayName)

        Custom skill installed via Flux.
        """

        let skillMdPath = skillDir.appendingPathComponent("SKILL.md")
        do {
            try skillMdContent.write(to: skillMdPath, atomically: true, encoding: .utf8)
        } catch {
            throw CustomInstallError.fileWriteFailed(error)
        }

        print("[SkillInstaller] Installed custom skill '\(displayName)' at \(skillDir.path)")
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
