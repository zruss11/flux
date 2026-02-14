import Foundation

struct FragmentRepairProcessor {

    // Matches a word fragment ending with a hyphen/dash followed by whitespace
    // and then the complete version of the word.
    // Example: "I wan- I want" → "I want"
    private static let fragmentPattern = try! NSRegularExpression(
        pattern: #"\b(\w+)-\s+\1"#,
        options: .caseInsensitive
    )

    // Maximum character count for the pre-dash portion of a word fragment
    // before it is considered an orphan and stripped.  Kept conservative
    // to avoid removing legitimate prefixes like "cross-" or "trans-".
    private static let maxOrphanFragmentLength = 3

    // Matches a broken word fragment (word + hyphen) at a word boundary that
    // is immediately followed by a space.  Used as a fallback to strip
    // orphaned fragments like "abso- the thing is" that don't repeat.
    private static let orphanFragmentPattern = try! NSRegularExpression(
        pattern: #"\b\w+-\s+"#,
        options: .caseInsensitive
    )

    // Collapse multiple spaces left behind after removals.
    private static let multiSpacePattern = try! NSRegularExpression(
        pattern: #" {2,}"#
    )

    /// Repairs speech fragments / stutters in transcribed text.
    ///
    /// - `"I wan- I want to go"` → `"I want to go"`
    /// - `"the abso- absolutely great"` → `"the absolutely great"`
    static func process(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Pass 1: Remove fragment + repeated full word ("wan- want" → "want")
        result = apply(regex: fragmentPattern, in: result, with: "$1")

        // Pass 2: Remove orphan fragments that didn't match a repeated word.
        // Only strip fragments that are clearly broken (short fragment < 6 chars
        // before the dash) to avoid false positives with legitimate hyphenated words.
        let nsResult = result as NSString
        let matches = orphanFragmentPattern.matches(
            in: result,
            range: NSRange(location: 0, length: nsResult.length)
        ).reversed()

        var mutableResult = result
        for match in matches {
            guard let range = Range(match.range, in: mutableResult) else { continue }
            let matched = String(mutableResult[range])
            // Only strip if the fragment part (before dash) is short
            let fragmentPart = matched.prefix(while: { $0 != "-" })
            if fragmentPart.count <= maxOrphanFragmentLength {
                mutableResult.replaceSubrange(range, with: "")
            }
        }
        result = mutableResult

        // Clean up spacing
        result = apply(regex: multiSpacePattern, in: result, with: " ")
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    private static func apply(regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
