import Foundation

struct IntentCorrectionProcessor {

    /// Trigger phrases that indicate the speaker is correcting themselves.
    /// When detected, the clause *before* the trigger is discarded and only
    /// the correction (after the trigger) is kept.
    ///
    /// All entries are lowercased — matching is done against a lowercased copy
    /// of the input text.
    private static let triggers = [
        "scratch that",
        "never mind",
        "correction",
        "actually",
        "i mean",
        "sorry",
        "wait",
        "no,",
    ]

    // Collapse multiple spaces left behind after removals.
    private static let multiSpacePattern = try! NSRegularExpression(
        pattern: #" {2,}"#
    )

    /// Handles self-corrections mid-sentence.
    ///
    /// - `"use the old API, wait, actually use the new API"` → `"use the new API"`
    /// - `"send it to John, no, send it to Sarah"` → `"send it to Sarah"`
    /// - `"open the scratch that close the window"` → `"close the window"`
    static func process(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Scan for the *last* occurrence of any trigger phrase. This handles
        // chained corrections like "A, wait, B, no, C" → "C".
        while let (_, range) = findLastTrigger(in: result) {
            // Keep everything after the trigger phrase.
            let afterTrigger = result[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespaces)

            guard !afterTrigger.isEmpty else {
                // Trigger at the very end with nothing after it — remove just
                // the trigger and stop.
                let beforeTrigger = result[..<range.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespaces)
                result = beforeTrigger
                break
            }

            // Optionally keep a sentence-level connector. If the text before
            // the trigger ends with a period, keep the part before as a
            // separate sentence, otherwise discard it entirely.
            let beforeTrigger = String(result[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))

            if beforeTrigger.hasSuffix(".") {
                result = beforeTrigger + " " + capitalizeFirst(afterTrigger)
            } else {
                result = afterTrigger
            }
        }

        // Clean up spacing
        let range = NSRange(result.startIndex..., in: result)
        result = Self.multiSpacePattern.stringByReplacingMatches(
            in: result, range: range, withTemplate: " "
        )
        result = result.trimmingCharacters(in: .whitespaces)

        // Recapitalize the first character.
        result = capitalizeFirst(result)

        return result
    }

    // MARK: - Private Helpers

    /// Finds the last occurrence of any trigger phrase in `text`, matching
    /// only on word boundaries to avoid false positives (e.g. "wait" inside
    /// "awaiting").
    private static func findLastTrigger(in text: String) -> (trigger: String, range: Range<String.Index>)? {
        let lowered = text.lowercased()
        var best: (trigger: String, range: Range<String.Index>)? = nil

        for trigger in triggers {
            // Build a word-boundary–aware pattern for the trigger.
            let escaped = NSRegularExpression.escapedPattern(for: trigger)
            // Triggers ending with punctuation (like "no,") should not
            // require a trailing word boundary.
            let needsTrailingBoundary = trigger.last?.isLetter ?? false
            let pattern = "\\b" + escaped + (needsTrailingBoundary ? "\\b" : "")
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let nsRange = NSRange(lowered.startIndex..., in: lowered)
            // Collect all matches and pick the last one.
            let matches = regex.matches(in: lowered, range: nsRange)
            guard let lastMatch = matches.last,
                  let matchRange = Range(lastMatch.range, in: lowered) else {
                continue
            }

            // Map the range from the lowered copy back to the original text.
            let startOffset = lowered.distance(from: lowered.startIndex, to: matchRange.lowerBound)
            let endOffset = lowered.distance(from: lowered.startIndex, to: matchRange.upperBound)
            let origStart = text.index(text.startIndex, offsetBy: startOffset)
            let origEnd = text.index(text.startIndex, offsetBy: endOffset)
            let origRange = origStart..<origEnd

            if let current = best {
                if origRange.lowerBound > current.range.lowerBound {
                    best = (trigger, origRange)
                }
            } else {
                best = (trigger, origRange)
            }
        }

        return best
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
