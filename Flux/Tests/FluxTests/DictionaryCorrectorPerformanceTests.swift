import XCTest
@testable import Flux

@MainActor
final class DictionaryCorrectorPerformanceTests: XCTestCase {

    func testPerformance() {
        // Create 100 entries to simulate a moderate dictionary size
        let entries = (0..<100).map { i in
            DictionaryEntry(text: "Replacement\(i)", aliases: ["alias\(i)"])
        }
        let text = "This is a test with alias50 and alias10 in it."

        // Measure execution time for 1000 iterations
        // The optimization should drastically reduce this time by caching regexes
        measure {
            for _ in 0..<1000 {
                _ = DictionaryCorrector.apply(text, using: entries)
            }
        }
    }

    func testCorrectnessCheck() {
        // Verify basic functionality still works correctly
        let entries = [
            DictionaryEntry(text: "Kubernetes", aliases: ["k8s"]),
            DictionaryEntry(text: "PostgreSQL", aliases: ["pg"]),
        ]

        let input = "Deploy k8s using pg database."
        let expected = "Deploy Kubernetes using PostgreSQL database."
        let result = DictionaryCorrector.apply(input, using: entries)
        XCTAssertEqual(result, expected)
    }

    func testEdgeCases() {
        // Verify edge cases handled correctly
        let entries = [
            DictionaryEntry(text: "Foo", aliases: ["foo"]),
            DictionaryEntry(text: "Bar", aliases: ["bar"]),
        ]

        // Case insensitivity
        XCTAssertEqual(DictionaryCorrector.apply("foo", using: entries), "Foo")
        XCTAssertEqual(DictionaryCorrector.apply("FOO", using: entries), "Foo")

        // Overlaps/Word boundaries
        XCTAssertEqual(DictionaryCorrector.apply("foobar", using: entries), "foobar") // Should not match inside word
        XCTAssertEqual(DictionaryCorrector.apply("foo bar", using: entries), "Foo Bar")
    }

    func testEqualLengthAliases() {
        // When two entries have aliases of the same length, the first entry wins deterministically
        let entries = [
            DictionaryEntry(text: "Alpha", aliases: ["abc"]),
            DictionaryEntry(text: "Beta", aliases: ["xyz"]),
        ]
        // Both aliases are length 3; each should independently resolve
        XCTAssertEqual(DictionaryCorrector.apply("abc", using: entries), "Alpha")
        XCTAssertEqual(DictionaryCorrector.apply("xyz", using: entries), "Beta")
        XCTAssertEqual(DictionaryCorrector.apply("abc and xyz", using: entries), "Alpha and Beta")
    }

    func testEmptyAndWhitespaceAliases() {
        // Empty or whitespace-only aliases should not cause crashes or incorrect matches
        let entries = [
            DictionaryEntry(text: "Valid", aliases: ["valid", "", "   "]),
        ]
        XCTAssertEqual(DictionaryCorrector.apply("valid", using: entries), "Valid")
        // Original text should pass through unchanged if only empty/whitespace aliases exist
        XCTAssertEqual(DictionaryCorrector.apply("hello world", using: entries), "hello world")
        // Verify non-word-char inputs aren't corrupted by empty alias matching
        XCTAssertEqual(DictionaryCorrector.apply("   ", using: entries), "   ")
        XCTAssertEqual(DictionaryCorrector.apply("(hello)", using: entries), "(hello)")
    }

    func testRegexSpecialCharactersInAliases() {
        // Aliases with regex special characters must be properly escaped
        let entries = [
            DictionaryEntry(text: "C++", aliases: ["c++"]),
            DictionaryEntry(text: "Money", aliases: ["$var"]),
            DictionaryEntry(text: "Question", aliases: ["why?"]),
        ]
        XCTAssertEqual(DictionaryCorrector.apply("I use c++", using: entries), "I use C++")
        XCTAssertEqual(DictionaryCorrector.apply("check $var now", using: entries), "check Money now")
        XCTAssertEqual(DictionaryCorrector.apply("oh why?", using: entries), "oh Question")
    }

    func testUnicodeAndEmojiAliases() {
        // Unicode and emoji should work correctly as aliases
        let entries = [
            DictionaryEntry(text: "Thumbs Up", aliases: ["👍"]),
            DictionaryEntry(text: "Café", aliases: ["cafe"]),
            DictionaryEntry(text: "日本語", aliases: ["nihongo"]),
        ]
        XCTAssertEqual(DictionaryCorrector.apply("👍", using: entries), "Thumbs Up")
        XCTAssertEqual(DictionaryCorrector.apply("cafe", using: entries), "Café")
        XCTAssertEqual(DictionaryCorrector.apply("nihongo", using: entries), "日本語")
    }
}
