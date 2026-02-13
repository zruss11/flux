import Foundation

struct DictionaryCorrector {

    // Cache for compiled regex and replacement map to avoid expensive recompilation.
    // Keyed by the dictionary entries themselves (which are Hashable).
    @MainActor
    private static var cache: (entries: [DictionaryEntry], regex: NSRegularExpression, replacements: [String: String])?

    @MainActor
    static func apply(_ text: String, using entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        let regex: NSRegularExpression
        let replacementsMap: [String: String]

        // Check if cache is valid (entries match)
        if let cached = cache, cached.entries == entries {
            regex = cached.regex
            replacementsMap = cached.replacements
        } else {
            // Rebuild cache
            // 1. Flatten entries to pairs (alias -> replacement)
            var pairs: [(alias: String, replacement: String)] = []
            for entry in entries {
                // Include the entry text itself as an alias to correct casing
                let allAliases = [entry.text] + entry.aliases
                for alias in allAliases {
                    pairs.append((alias: alias, replacement: entry.text))
                }
            }

            // 2. Sort pairs by alias length descending (longest match wins in regex alternation)
            pairs.sort { $0.alias.count > $1.alias.count }

            // 3. Deduplicate aliases and build replacement map
            // Use lowercased alias as key because regex is case-insensitive.
            // Since pairs are sorted by length, and we iterate in order, this preserves priority if needed.
            // However, for identical aliases (same string), we only need one entry.
            var map: [String: String] = [:]
            var uniqueAliases: [String] = []
            var seen = Set<String>()

            for pair in pairs {
                let key = pair.alias.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    uniqueAliases.append(pair.alias)
                    map[key] = pair.replacement
                }
            }

            guard !uniqueAliases.isEmpty else { return text }

            // 4. Construct a single regex pattern
            // Pattern: (?<!\w)(?:escapedAlias1|escapedAlias2|...)(?!\w)
            let pattern = uniqueAliases.map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            let fullPattern = "(?<!\\w)(?:\(pattern))(?!\\w)"

            do {
                regex = try NSRegularExpression(pattern: fullPattern, options: .caseInsensitive)
                replacementsMap = map
                cache = (entries, regex, map)
            } catch {
                print("Failed to compile regex for dictionary: \(error)")
                return text
            }
        }

        var result = text
        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: nsRange)

        var replacements: [(range: Range<String.Index>, replacement: String)] = []

        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let matchedString = String(result[range])

            // Look up replacement using lowercased match
            if let replacement = replacementsMap[matchedString.lowercased()] {
                // Only replace if the text is actually different (e.g. casing correction)
                if matchedString != replacement {
                    replacements.append((range: range, replacement: replacement))
                }
            }
        }

        // Apply from back to front so earlier indices stay valid.
        for rep in replacements.reversed() {
            result.replaceSubrange(rep.range, with: rep.replacement)
        }

        return result
    }
}
