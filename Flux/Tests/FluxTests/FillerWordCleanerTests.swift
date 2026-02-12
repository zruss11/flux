import XCTest
@testable import Flux

final class FillerWordCleanerTests: XCTestCase {

    func testRemovesFillerWords() {
        let input = "um, this is uh a test with umm filler words."
        let expected = "This is a test with filler words."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testCollapsesRepeatedWords() {
        let input = "the the quick brown fox fox jumps"
        let expected = "The quick brown fox jumps"
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testCollapsesMultipleSpaces() {
        let input = "This  has    too many   spaces."
        let expected = "This has too many spaces."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testFixesOrphanCommas() {
        let input = "Hello , , world."
        let expected = "Hello, world."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testTrimsCommasAfterPeriods() {
        let input = "This is a sentence. , And another."
        let expected = "This is a sentence. And another."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testRecapitalizesAfterPeriods() {
        let input = "hello world. this is a test. another sentence."
        let expected = "Hello world. This is a test. Another sentence."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testCapitalizesFirstLetter() {
        let input = "hello world"
        let expected = "Hello world"
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testComplexExample() {
        let input = "um, hello  hello world. , this is uh a test."
        let expected = "Hello world. This is a test."
        XCTAssertEqual(FillerWordCleaner.clean(input), expected)
    }

    func testEmptyString() {
        XCTAssertEqual(FillerWordCleaner.clean(""), "")
    }

    func testNoChangesNeeded() {
        let input = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(FillerWordCleaner.clean(input), input)
    }
}
