import Foundation

struct DictionaryCorrector {

    @MainActor
    static func apply(_ text: String, using entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        var result = text

        let pairs = entries.flatMap { entry -> [(alias: String, replacement: String)] in
            if entry.aliases.isEmpty {
                return [(alias: entry.text, replacement: entry.text)]
            }
            return entry.aliases.map { (alias: $0, replacement: entry.text) }
        }
        .sorted { $0.alias.count > $1.alias.count }

        for pair in pairs {
            let escaped = NSRegularExpression.escapedPattern(for: pair.alias)
            let pattern = "\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: pair.replacement)
            )
        }

        return result
    }
}
