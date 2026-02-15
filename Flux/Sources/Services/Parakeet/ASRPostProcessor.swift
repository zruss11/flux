import Foundation
import os

// MARK: - ASRPostProcessor

/// Multi-stage text post-processing pipeline for ASR output.
///
/// Inspired by Almond's ASRProcessor, this applies several deterministic text
/// transformations to clean up raw transcript output. Each stage can be
/// individually toggled via UserDefaults flags.
///
/// Pipeline:
/// ```
/// Raw transcript
///   → Fragment repair   (fix stutters)
///   → Intent correction (handle self-corrections)
///   → Repeat removal    (deduplicate repeated phrases)
///   → Number conversion (spoken numbers → digits)
///   → Output
/// ```
///
/// This operates on top of the existing `FillerWordCleaner` (filler removal,
/// repeated word collapse, punctuation cleanup).
struct ASRPostProcessor {

    // MARK: - Configuration

    struct Config: Sendable {
        var enableFragmentRepair: Bool
        var enableIntentCorrection: Bool
        var enableRepeatRemoval: Bool
        var enableNumberConversion: Bool

        /// Load configuration from UserDefaults with sensible defaults.
        static func fromDefaults() -> Config {
            let defaults = UserDefaults.standard
            return Config(
                enableFragmentRepair: defaults.object(forKey: "asrEnableFragmentRepair") as? Bool ?? true,
                enableIntentCorrection: defaults.object(forKey: "asrEnableIntentCorrection") as? Bool ?? true,
                enableRepeatRemoval: defaults.object(forKey: "asrEnableRepeatRemoval") as? Bool ?? true,
                enableNumberConversion: defaults.object(forKey: "asrEnableNumberConversion") as? Bool ?? true
            )
        }

        /// All stages enabled.
        static let allEnabled = Config(
            enableFragmentRepair: true,
            enableIntentCorrection: true,
            enableRepeatRemoval: true,
            enableNumberConversion: true
        )
    }

    // MARK: - Public API

    /// Apply the full post-processing pipeline to raw transcript text.
    ///
    /// - Parameters:
    ///   - text: Raw transcript from the ASR engine.
    ///   - config: Configuration controlling which stages are active.
    /// - Returns: Processed text.
    static func process(_ text: String, config: Config = .fromDefaults()) -> String {
        var result = text

        if config.enableFragmentRepair {
            result = repairFragments(result)
        }

        if config.enableIntentCorrection {
            result = correctIntent(result)
        }

        if config.enableRepeatRemoval {
            result = removeRepeatedPhrases(result)
        }

        if config.enableNumberConversion {
            result = convertNumbers(result)
        }

        // Final cleanup: collapse multiple spaces, trim.
        result = result.replacingOccurrences(
            of: "  +",
            with: " ",
            options: .regularExpression
        )
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Fragment Repair

    /// Fix speech fragments/stutters.
    ///
    /// Examples:
    /// - "I wan- I want to" → "I want to"
    /// - "the app- application" → "the application"
    private static let fragmentPattern = try! NSRegularExpression(
        pattern: #"\b(\w+)-\s+(\w+)"#,
        options: .caseInsensitive
    )

    static func repairFragments(_ text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text

        // Find word fragments (word followed by hyphen and space).
        let matches = fragmentPattern.matches(in: text, range: range).reversed()

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fragmentRange = Range(match.range(at: 1), in: result),
                  let fullWordRange = Range(match.range(at: 2), in: result),
                  let fullMatchRange = Range(match.range, in: result) else { continue }

            let fragment = String(result[fragmentRange]).lowercased()
            let fullWord = String(result[fullWordRange])

            // If the full word starts with the fragment, it's a stutter — keep only the full word.
            if fullWord.lowercased().hasPrefix(fragment) {
                result.replaceSubrange(fullMatchRange, with: fullWord)
            }
        }

        return result
    }

    // MARK: - Intent Correction

    /// Handle self-corrections in speech.
    ///
    /// Patterns detected:
    /// - "X, wait, actually Y" → "Y"
    /// - "X, no, Y" → "Y"
    /// - "X, I mean Y" → "Y"
    /// - "X, sorry, Y" → "Y"
    /// - "X, actually Y" → "Y"
    private static let intentCorrectionPatterns: [(NSRegularExpression, String)] = {
        // Patterns require the correction phrase to appear after a comma or
        // clause boundary to avoid false positives on normal prose like
        // "I actually like this".
        let patterns: [(String, String)] = [
            (#"(.+?),\s+wait,?\s+actually\s+(.+)"#, "$2"),
            (#"(.+?),\s+no,?\s+(?:wait,?\s+)?(.+)"#, "$2"),
            (#"(.+?),\s+I mean\s+(.+)"#, "$2"),
            (#"(.+?),\s+sorry,?\s+(.+)"#, "$2"),
            (#"(.+?),\s+actually,?\s+(.+)"#, "$2"),
            (#"(.+?),\s+or rather,?\s+(.+)"#, "$2"),
        ]
        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return (regex, replacement)
        }
    }()

    static func correctIntent(_ text: String) -> String {
        var result = text

        for (regex, replacement) in intentCorrectionPatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }

        return result
    }

    // MARK: - Repeat Removal

    /// Remove repeated consecutive phrases (beyond simple word repetition).
    ///
    /// Examples:
    /// - "send the update send the update" → "send the update"
    /// - "please check please check the file" → "please check the file"
    private static let phraseRepeatPattern = try! NSRegularExpression(
        pattern: #"\b((?:\w+\s+){0,4}\w+)\s+\1\b"#,
        options: .caseInsensitive
    )

    static func removeRepeatedPhrases(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return phraseRepeatPattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1"
        )
    }

    // MARK: - Number Conversion

    /// Convert spoken number words to digits.
    ///
    /// Examples:
    /// - "one hundred twenty three" → "123"
    /// - "forty two" → "42"
    /// - "one thousand two hundred" → "1200"
    /// - "zero" → "0"

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90
    ]

    private static let multipliers: [String: Int] = [
        "hundred": 100,
        "thousand": 1000,
        "million": 1_000_000,
        "billion": 1_000_000_000
    ]

    private static let allNumberWordPattern: NSRegularExpression = {
        let allWords = Array(numberWords.keys) + Array(multipliers.keys) + ["and"]
        let pattern = allWords.sorted(by: { $0.count > $1.count })
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(
            pattern: #"\b((?:(?:"# + pattern + #")[\s-]*){2,})\b"#,
            options: .caseInsensitive
        )
    }()

    static func convertNumbers(_ text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = text

        let matches = allNumberWordPattern.matches(in: text, range: range).reversed()

        for match in matches {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let matchedText = String(result[matchRange])
                .trimmingCharacters(in: .whitespaces)

            if let number = parseSpokenNumber(matchedText) {
                let formatted = formatNumber(number)
                // Preserve a trailing space if the match consumed one.
                let fullMatch = String(result[matchRange])
                let suffix = fullMatch.hasSuffix(" ") ? " " : ""
                result.replaceSubrange(matchRange, with: formatted + suffix)
            }
        }

        return result
    }

    /// Parse a sequence of spoken number words into an integer.
    private static func parseSpokenNumber(_ text: String) -> Int? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "and" }

        guard !words.isEmpty else { return nil }

        var total = 0
        var current = 0
        var hasNumber = false

        for word in words {
            if let value = numberWords[word] {
                current += value
                hasNumber = true
            } else if let multiplier = multipliers[word] {
                if current == 0 { current = 1 }
                if multiplier >= 1000 {
                    total += current * multiplier
                    current = 0
                } else {
                    current *= multiplier
                }
                hasNumber = true
            }
        }

        total += current

        return hasNumber ? total : nil
    }

    /// Format a number with comma separators for readability.
    private static func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
