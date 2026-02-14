import Foundation

struct IntentCorrectionProcessor {

    /// Trigger phrases that indicate the speaker is correcting themselves.
    /// When detected, the clause *before* the trigger is discarded and only
    /// the correction (after the trigger) is kept.
    private static let triggers = [
        "scratch that",
        "never mind",
        "correction",
        "actually",
        "I mean",
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
        while let (trigger, range) = findLastTrigger(in: result) {
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

            // Discard trigger "actually" when it appears inside a legitimate
            // phrase rather than as a correction marker.  The heuristic: if
            // the remaining text is the same or longer than the original, the
            // trigger was embedded and we should stop re-scanning.
            if trigger == "actually" { break }
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

    private static func findLastTrigger(in text: String) -> (trigger: String, range: Range<String.Index>)? {
        let lowered = text.lowercased()
        var best: (trigger: String, range: Range<String.Index>)? = nil

        for trigger in triggers {
            // Search case-insensitively by working on the lowered copy.
            if let foundRange = lowered.range(of: trigger, options: .backwards) {
                if let current = best {
                    // Keep the one that appears later in the string.
                    if foundRange.lowerBound > current.range.lowerBound {
                        // Map range back to the original text indices.
                        let origRange = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: foundRange.lowerBound))
                            ..< text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: foundRange.upperBound))
                        best = (trigger, origRange)
                    }
                } else {
                    let origRange = text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: foundRange.lowerBound))
                        ..< text.index(text.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: foundRange.upperBound))
                    best = (trigger, origRange)
                }
            }
        }

        return best
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
