import Foundation

struct DictionaryCorrector {

    @MainActor
    static func apply(_ text: String, using entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        var result = text

        let pairs = entries.flatMap { entry -> [(alias: String, replacement: String)] in
            var matches = [entry.text]
            matches.append(contentsOf: entry.aliases)

            var seen = Set<String>()
            return matches.compactMap { match in
                guard seen.insert(match).inserted else { return nil }
                return (alias: match, replacement: entry.text)
            }
        }
        .sorted { $0.alias.count > $1.alias.count }

        // Collect all matches against the original text to prevent cascading rewrites.
        var replacements: [(range: Range<String.Index>, replacement: String)] = []

        for pair in pairs {
            let escaped = NSRegularExpression.escapedPattern(for: pair.alias)
            let pattern = "(?<!\\w)\(escaped)(?!\\w)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let nsRange = NSRange(result.startIndex..., in: result)
            for match in regex.matches(in: result, range: nsRange) {
                guard let swiftRange = Range(match.range, in: result) else { continue }
                let overlaps = replacements.contains { $0.range.overlaps(swiftRange) }
                if !overlaps {
                    replacements.append((range: swiftRange, replacement: pair.replacement))
                }
            }
        }

        // Apply from back to front so earlier indices stay valid.
        for rep in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(rep.range, with: rep.replacement)
        }

        return result
    }
}
