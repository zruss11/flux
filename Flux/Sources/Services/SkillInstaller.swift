import Foundation

enum SkillInstaller {
    enum InstallError: Error {
        case catalogEntryNotFound
        case directoryCreationFailed(Error)
        case fileWriteFailed(Error)
        case dependencyInstallFailed(String, Int32)
        case brewNotFound
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

    /// Installs a catalog skill into the local skills directory.
    /// Dependencies are resolved before creating files so failed installs
    /// do not leave partially installed skills behind.
    static func install(directoryName: String) async throws {
        guard let entry = SkillCatalog.recommended.first(where: { $0.directoryName == directoryName }) else {
            throw InstallError.catalogEntryNotFound
        }

        // Install CLI dependencies (e.g. brew formulas) before creating any local files.
        for dep in entry.dependencies {
            let allPresent = dep.bins.allSatisfy { isBinaryOnPath($0) }
            if allPresent {
                print("[SkillInstaller] Dependencies for '\(entry.displayName)' already satisfied")
                continue
            }

            switch dep.kind {
            case .brew:
                try await installBrewDependency(dep)
            }
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
            // Best-effort rollback for partial installs.
            try? fm.removeItem(at: skillDir)
            throw InstallError.fileWriteFailed(error)
        }

        print("[SkillInstaller] Installed skill '\(entry.displayName)' at \(skillDir.path)")
    }

    // MARK: - Brew Dependency Installation

    /// Installs a Homebrew dependency for a skill.
    private static func installBrewDependency(_ dep: SkillDependency) async throws {
        guard isBinaryOnPath("brew") else {
            throw InstallError.brewNotFound
        }

        // If the formula includes a tap (e.g. "steipete/tap/imsg"), brew handles tapping automatically.
        // But if an explicit tap is set, tap first for clarity.
        if let tap = dep.tap {
            let tapResult = await runProcess("/usr/bin/env", arguments: ["brew", "tap", tap])
            if tapResult.status != 0 {
                print("[SkillInstaller] Warning: brew tap '\(tap)' exited \(tapResult.status): \(tapResult.output)")
            }
        }

        let result = await runProcess("/usr/bin/env", arguments: ["brew", "install", dep.formula])
        if result.status != 0 {
            throw InstallError.dependencyInstallFailed(dep.formula, result.status)
        }
        print("[SkillInstaller] Installed brew dependency '\(dep.formula)'")
    }

    /// Returns true when a binary is available on PATH.
    private static func isBinaryOnPath(_ name: String) -> Bool {
        let result = Process()
        result.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        result.arguments = [name]
        result.standardOutput = FileHandle.nullDevice
        result.standardError = FileHandle.nullDevice
        do {
            try result.run()
            result.waitUntilExit()
            return result.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Runs a child process and drains combined stdout/stderr while it is executing.
    private static func runProcess(_ path: String, arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                }
            }
        }
    }

    /// Uninstalls a skill directory from all known install roots.
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

    /// Installs a custom skill scaffold with a generated `SKILL.md`.
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

    /// Resolves the preferred install directory for skills by preferring
    /// project-local `.agents/skills` and falling back to `~/.claude/skills`.
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
