import Foundation

struct NumberConversionProcessor {

    // MARK: - Word → Value Tables

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let multipliers: [String: Int] = [
        "hundred": 100,
        "thousand": 1_000,
        "million": 1_000_000,
        "billion": 1_000_000_000,
    ]

    private static let ordinalSuffixes: [String: String] = [
        "first": "1st", "second": "2nd", "third": "3rd", "fourth": "4th",
        "fifth": "5th", "sixth": "6th", "seventh": "7th", "eighth": "8th",
        "ninth": "9th", "tenth": "10th", "eleventh": "11th", "twelfth": "12th",
        "thirteenth": "13th", "fourteenth": "14th", "fifteenth": "15th",
        "sixteenth": "16th", "seventeenth": "17th", "eighteenth": "18th",
        "nineteenth": "19th", "twentieth": "20th", "thirtieth": "30th",
        "fortieth": "40th", "fiftieth": "50th", "sixtieth": "60th",
        "seventieth": "70th", "eightieth": "80th", "ninetieth": "90th",
        "hundredth": "100th", "thousandth": "1000th",
    ]

    /// All words that are part of a number expression (used to identify runs).
    private static let numberWords: Set<String> = {
        var words = Set<String>()
        words.formUnion(ones.keys)
        words.formUnion(tens.keys)
        words.formUnion(multipliers.keys)
        words.insert("and")
        words.insert("a")  // "a hundred", "a thousand"
        return words
    }()

    // MARK: - Public API

    /// Converts spoken number expressions into digit form.
    ///
    /// - `"one hundred"` → `"100"`
    /// - `"twenty three"` → `"23"`
    /// - `"one thousand two hundred"` → `"1200"`
    /// - `"first"` → `"1st"`
    static func process(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // Tokenize
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return text }

        var result: [String] = []
        var i = 0

        while i < words.count {
            let word = words[i]
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            // Check for ordinal words first (single-word replacement).
            if let ordinal = ordinalSuffixes[lower] {
                // Preserve any trailing punctuation from the original word.
                let trailing = trailingPunctuation(word)
                result.append(ordinal + trailing)
                i += 1
                continue
            }

            // Not a number word — pass through.
            guard isNumberWord(lower) else {
                result.append(word)
                i += 1
                continue
            }

            // Collect a run of number words.
            var run: [String] = []
            var j = i
            while j < words.count {
                let w = words[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                if isNumberWord(w) {
                    run.append(w)
                    j += 1
                } else {
                    break
                }
            }

            // Strip "and" at start/end of the run (it's a connector, not a value).
            while run.first == "and" { run.removeFirst(); i += 1 }
            while run.last == "and" { run.removeLast(); j -= 1 }

            // If run collapsed or it's just "a" without a multiplier, pass original words.
            if run.isEmpty || (run.count == 1 && run[0] == "a") {
                result.append(words[i])
                i += 1
                continue
            }

            // Build the number from the run.
            if let value = buildNumber(from: run) {
                // Preserve trailing punctuation from the last consumed word.
                let trailing = trailingPunctuation(words[j - 1])
                result.append(String(value) + trailing)
            } else {
                // Could not parse — keep original words.
                for k in i..<j {
                    result.append(words[k])
                }
            }
            i = j
        }

        return result.joined(separator: " ")
    }

    // MARK: - Number Builder

    /// Builds an integer from a run of number words using a simple
    /// accumulator approach that handles compound numbers like
    /// "two thousand three hundred forty five" → 2345.
    private static func buildNumber(from words: [String]) -> Int? {
        // Filter out "and" which is purely a connector.
        let tokens = words.filter { $0 != "and" }
        guard !tokens.isEmpty else { return nil }

        // Special case: single word that is only in ones or tens.
        if tokens.count == 1 {
            let w = tokens[0]
            if w == "a" { return nil }
            if let v = ones[w] { return v }
            if let v = tens[w] { return v }
            if let v = multipliers[w] { return v }
            return nil
        }

        var total = 0
        var current = 0

        for token in tokens {
            if token == "a" {
                current = 1
            } else if let v = ones[token] {
                current += v
            } else if let v = tens[token] {
                current += v
            } else if token == "hundred" {
                current = (current == 0 ? 1 : current) * 100
            } else if let mult = multipliers[token], mult >= 1000 {
                current = (current == 0 ? 1 : current) * mult
                total += current
                current = 0
            } else {
                return nil // unknown token
            }
        }

        total += current
        return total > 0 ? total : nil
    }

    // MARK: - Helpers

    private static func isNumberWord(_ word: String) -> Bool {
        numberWords.contains(word)
    }

    /// Returns trailing punctuation (,.!? etc.) from a word.
    private static func trailingPunctuation(_ word: String) -> String {
        var trailing = ""
        for char in word.reversed() {
            if char.isPunctuation || char == "," || char == "." || char == "!" || char == "?" {
                trailing = String(char) + trailing
            } else {
                break
            }
        }
        return trailing
    }
}
