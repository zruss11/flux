import Foundation

struct FillerWordCleaner {

    static func clean(_ text: String) -> String {
        var result = text

        // Remove standalone filler words (with optional trailing comma)
        result = applyPattern(#"\b(um|uh|uhh|umm|hmm|er|erm)\b,?\s*"#, in: result, with: " ")

        // Collapse repeated words ("the the" -> "the")
        result = applyPatternKeepingGroup(#"\b(\w+)\s+\1\b"#, in: result)

        // Collapse multiple spaces to single space
        result = applyPattern(#" {2,}"#, in: result, with: " ")

        // Fix orphan commas (", ," -> ",")
        result = applyPattern(#",\s*,"#, in: result, with: ",")

        // Trim commas after periods (". ," -> ".")
        result = applyPattern(#"\.\s*,"#, in: result, with: ".")

        // Re-capitalize first letter after periods
        result = recapitalizeAfterPeriods(result)

        // Capitalize the very first letter
        result = capitalizeFirst(result)

        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private

    private static func applyPattern(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func applyPatternKeepingGroup(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func recapitalizeAfterPeriods(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\.\s+([a-z])"#) else {
            return text
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text

        let matches = regex.matches(in: text, range: range).reversed()
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
