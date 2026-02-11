import Foundation
import SwiftUI

enum SkillsLoader {

    static func loadSkills() async -> [Skill] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var searchDirs = [
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".agents/skills"),
        ]

        // Dev/prod convenience: if the app bundle contains packaged skills, include them.
        // `scripts/dev.sh` copies repo `.agents/skills` into `Contents/Resources/agents/skills`.
        if let res = Bundle.main.resourceURL {
            searchDirs.append(res.appendingPathComponent("agents/skills"))
            searchDirs.append(res.appendingPathComponent("skills"))
        }

        let fm = FileManager.default
        var seen = Set<String>() // dedupe by directory name
        var skills: [Skill] = []

        for skillsDir in searchDirs {
            let dirExists = fm.fileExists(atPath: skillsDir.path)
            print("[SkillsLoader] Checking \(skillsDir.path) — exists: \(dirExists)")
            guard dirExists else { continue }

            guard let entries = try? fm.contentsOfDirectory(
                at: skillsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                print("[SkillsLoader] Failed to list contents of \(skillsDir.path)")
                continue
            }

            print("[SkillsLoader] Found \(entries.count) entries in \(skillsDir.lastPathComponent)")

            for entry in entries {
                let dirName = entry.lastPathComponent
                guard !seen.contains(dirName) else { continue }

                let resolved = entry.resolvingSymlinksInPath()

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
                skills.append(Skill(
                    id: UUID(),
                    name: name,
                    directoryName: dirName,
                    description: description,
                    icon: Skill.iconForName(name),
                    color: Skill.colorForName(dirName),
                    isInstalled: true
                ))
            }
        }

        print("[SkillsLoader] Loaded \(skills.count) skills total")
        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                isInstalled: false
            ))
        }

        return installed + recommended.sorted {
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
