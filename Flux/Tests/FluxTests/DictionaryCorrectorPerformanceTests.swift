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
}
