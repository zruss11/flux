import Foundation
import os
import SwiftUI

enum SkillsLoader {

    // Resolve project skills by searching for a `.agents/skills` directory near likely project roots.
    // This is primarily for Debug/Xcode runs where repo skills are not bundled into the app resources.
    private static func discoverProjectSkillsDir() -> URL? {
        let fm = FileManager.default

        var candidates: [URL] = []

        let env = ProcessInfo.processInfo.environment
        for key in ["FLUX_PROJECT_ROOT", "FLUX_REPO_ROOT", "SRCROOT", "PROJECT_DIR"] {
            if let p = env[key], !p.isEmpty {
                candidates.append(URL(fileURLWithPath: p, isDirectory: true))
            }
        }

        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))

        // Walk upward from each candidate until we find `.agents/skills`.
        // This keeps the behavior flexible even if the working directory is a subfolder.
        for start in candidates {
            var cur = start
            var seen = Set<String>()
            while true {
                let path = cur.standardizedFileURL.path
                if seen.contains(path) { break }
                seen.insert(path)

                let skillsDir = cur.appendingPathComponent(".agents/skills")
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: skillsDir.path, isDirectory: &isDir), isDir.boolValue {
                    Log.skills.debug("Discovered project skills dir at \(skillsDir.path)")
                    return skillsDir
                }

                let parent = cur.deletingLastPathComponent()
                if parent.path == cur.path { break }
                cur = parent
            }
        }

        return nil
    }

    static func loadSkills() async -> [Skill] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var searchDirs: [URL] = []

        if let projectSkills = discoverProjectSkillsDir() {
            // Prefer project skills over global ones when directory names collide.
            searchDirs.append(projectSkills)
        }

        searchDirs.append(contentsOf: [
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".agents/skills"),
        ])

        // Dev/prod convenience: if the app bundle contains packaged skills, include them.
        // `scripts/dev.sh` copies repo `.agents/skills` into `Contents/Resources/agents/skills`.
        if let res = Bundle.main.resourceURL {
            searchDirs.append(res.appendingPathComponent("agents/skills"))
            searchDirs.append(res.appendingPathComponent("skills"))
        }

        let fm = FileManager.default
        var seen = Set<String>() // dedupe by slash-command path
        var skills: [Skill] = []

        for skillsDir in searchDirs {
            let dirExists = fm.fileExists(atPath: skillsDir.path)
            Log.skills.debug("Checking \(skillsDir.path) — exists: \(dirExists)")
            guard dirExists else { continue }

            let skillEntries = discoverCommandDirectories(in: skillsDir, fileManager: fm)
            guard !skillEntries.isEmpty else {
                Log.skills.warning("Failed to list contents of \(skillsDir.path)")
                continue
            }

            Log.skills.debug("Found \(skillEntries.count) skill directories in \(skillsDir.lastPathComponent)")

            for skillEntry in skillEntries {
                let dirName = relativeCommandName(for: skillEntry, in: skillsDir) ?? skillEntry.lastPathComponent
                guard !seen.contains(dirName) else { continue }

                let resolved = skillEntry.resolvingSymlinksInPath()

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                let skillMdPath = resolved.appendingPathComponent("SKILL.md")
                guard fm.fileExists(atPath: skillMdPath.path),
                      let content = try? String(contentsOf: skillMdPath, encoding: .utf8) else { continue }

                let frontmatter = parseFrontmatter(content)
                let name = frontmatter["name"] ?? dirName
                let description = frontmatter["description"]

                seen.insert(dirName)
                let permissions = SkillCatalog.recommended
                    .first { $0.directoryName == dirName }?
                    .requiredPermissions ?? []
                skills.append(Skill(
                    id: UUID(),
                    name: name,
                    directoryName: dirName,
                    description: description,
                    icon: Skill.iconForName(name),
                    color: Skill.colorForName(dirName),
                    isInstalled: true,
                    requiredPermissions: permissions
                ))
            }
        }

        Log.skills.info("Loaded \(skills.count) skills total")
        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Discovery

    /// Finds skill directories by locating `SKILL.md` files under the given root.
    private static func discoverCommandDirectories(in root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "SKILL.md" {
                results.append(url.deletingLastPathComponent())
            }
        }
        return results
    }

    /// Computes a slash-command-safe path relative to the given root directory.
    private static func relativeCommandName(for skillDir: URL, in root: URL) -> String? {
        let normalizedRoot = root.standardizedFileURL
        let normalizedSkill = skillDir.standardizedFileURL

        let rootComponents = normalizedRoot.pathComponents
        let skillComponents = normalizedSkill.pathComponents
        guard skillComponents.count > rootComponents.count else { return nil }
        return skillComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

    // MARK: - Load with Recommendations

    static func loadSkillsWithRecommendations() async -> [Skill] {
        let installed = await loadSkills()
        let installedDirNames = Set(installed.map { $0.directoryName })

        var recommended: [Skill] = []
        for entry in SkillCatalog.recommended {
            guard !installedDirNames.contains(entry.directoryName) else { continue }
            recommended.append(Skill(
                id: UUID(),
                name: entry.displayName,
                directoryName: entry.directoryName,
                description: entry.description,
                icon: Skill.iconForName(entry.displayName),
                color: Skill.colorForName(entry.directoryName),
                isInstalled: false,
                requiredPermissions: entry.requiredPermissions
            ))
        }

        // Unified alphabetical sort across installed and recommended skills.
        return (installed + recommended).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - YAML Frontmatter Parser

    private static func parseFrontmatter(_ markdown: String) -> [String: String] {
        guard markdown.hasPrefix("---\n") else { return [:] }

        let searchStart = markdown.index(markdown.startIndex, offsetBy: 4)
        guard let endRange = markdown.range(of: "\n---", range: searchStart..<markdown.endIndex) else { return [:] }

        let yamlString = String(markdown[searchStart..<endRange.lowerBound])
        return parseSimpleYaml(yamlString)
    }

    private static func parseSimpleYaml(_ yaml: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""
        var inMultiline = false

        let lines = yaml.components(separatedBy: "\n")

        for line in lines {
            if inMultiline {
                if !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                    if let key = currentKey {
                        result[key] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    inMultiline = false
                    currentKey = nil
                } else {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        currentValue += (currentValue.isEmpty ? "" : " ") + trimmed
                    }
                    continue
                }
            }

            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            guard !key.isEmpty, !key.contains(" ") else { continue }

            if value == "|" || value == ">" || value == ">-" || value == "|-" {
                currentKey = key
                currentValue = ""
                inMultiline = true
            } else if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                result[key] = String(value.dropFirst().dropLast())
            } else {
                result[key] = value
            }
        }

        // Flush remaining multiline
        if inMultiline, let key = currentKey {
            result[key] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}
