import Foundation

struct FillerWordCleaner {

    // MARK: - Compiled Regular Expressions

    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"\b(um|uh|uhh|umm|hmm|er|erm)\b,?\s*"#,
        options: .caseInsensitive
    )

    private static let repeatedWordPattern = try! NSRegularExpression(
        pattern: #"\b(\w+)\s+\1\b"#,
        options: .caseInsensitive
    )

    private static let multipleSpacesPattern = try! NSRegularExpression(
        pattern: #" {2,}"#,
        options: .caseInsensitive
    )

    private static let orphanCommaPattern = try! NSRegularExpression(
        pattern: #",\s*,"#,
        options: .caseInsensitive
    )

    private static let periodCommaPattern = try! NSRegularExpression(
        pattern: #"\.\s*,"#,
        options: .caseInsensitive
    )

    private static let spaceBeforeCommaPattern = try! NSRegularExpression(
        pattern: #"\s+,"#
    )

    private static let recapitalizePattern = try! NSRegularExpression(
        pattern: #"\.\s+([a-z])"#
    )

    // MARK: - Public API

    static func clean(_ text: String) -> String {
        var result = text

        // Remove standalone filler words (with optional trailing comma)
        result = apply(regex: fillerPattern, in: result, with: " ")

        // Collapse repeated words ("the the" -> "the")
        result = applyKeepingGroup(regex: repeatedWordPattern, in: result)

        // Collapse multiple spaces to single space
        result = apply(regex: multipleSpacesPattern, in: result, with: " ")

        // Fix orphan commas (", ," -> ",")
        result = apply(regex: orphanCommaPattern, in: result, with: ",")

        // Normalize space before comma (" ," -> ",")
        result = apply(regex: spaceBeforeCommaPattern, in: result, with: ",")

        // Trim commas after periods (". ," -> ".")
        result = apply(regex: periodCommaPattern, in: result, with: ".")

        // Re-capitalize first letter after periods
        result = recapitalizeAfterPeriods(result)

        // Trim whitespace before capitalizing so leading spaces don't prevent capitalization
        result = result.trimmingCharacters(in: .whitespaces)

        // Capitalize the very first letter
        result = capitalizeFirst(result)

        return result
    }

    // MARK: - Private Helpers

    private static func apply(regex: NSRegularExpression, in text: String, with replacement: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func applyKeepingGroup(regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func recapitalizeAfterPeriods(_ text: String) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        var result = text

        let matches = recapitalizePattern.matches(in: text, range: range).reversed()
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let letterRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let letter = String(result[letterRange]).uppercased()
            let fullMatch = String(result[fullRange])
            let replaced = fullMatch.dropLast(1) + letter
            result.replaceSubrange(fullRange, with: replaced)
        }
        return result
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
