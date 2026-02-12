import XCTest
@testable import Flux

@MainActor
final class DictionaryCorrectorTests: XCTestCase {

    func testBasicReplacement() {
        let entries = [DictionaryEntry(text: "Kubernetes", aliases: ["kuber nettys"])]
        let result = DictionaryCorrector.apply("run kuber nettys apply", using: entries)
        XCTAssertEqual(result, "run Kubernetes apply")
    }

    func testCaseInsensitive() {
        let entries = [DictionaryEntry(text: "PostgreSQL", aliases: ["post gress q l"])]
        let result = DictionaryCorrector.apply("use POST GRESS Q L database", using: entries)
        XCTAssertEqual(result, "use PostgreSQL database")
    }

    func testWordBoundaryRespected() {
        let entries = [DictionaryEntry(text: "the", aliases: ["the"])]
        let result = DictionaryCorrector.apply("other there them", using: entries)
        XCTAssertEqual(result, "other there them")
    }

    func testMultipleAliases() {
        let entries = [DictionaryEntry(text: "kubectl", aliases: ["cube cuddle", "cube cuttle"])]
        XCTAssertEqual(
            DictionaryCorrector.apply("run cube cuddle get pods", using: entries),
            "run kubectl get pods"
        )
        XCTAssertEqual(
            DictionaryCorrector.apply("run cube cuttle apply", using: entries),
            "run kubectl apply"
        )
    }

    func testNoAliasesUsesTextAsMatch() {
        let entries = [DictionaryEntry(text: "iPhone")]
        let result = DictionaryCorrector.apply("I love my iphone", using: entries)
        XCTAssertEqual(result, "I love my iPhone")
    }

    func testEmptyDictionary() {
        let result = DictionaryCorrector.apply("hello world", using: [])
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyText() {
        let entries = [DictionaryEntry(text: "test", aliases: ["tset"])]
        XCTAssertEqual(DictionaryCorrector.apply("", using: entries), "")
    }

    func testMultipleEntries() {
        let entries = [
            DictionaryEntry(text: "Kubernetes", aliases: ["kuber nettys"]),
            DictionaryEntry(text: "PostgreSQL", aliases: ["post gress"]),
        ]
        let result = DictionaryCorrector.apply("deploy to kuber nettys with post gress", using: entries)
        XCTAssertEqual(result, "deploy to Kubernetes with PostgreSQL")
    }

    func testLongestMatchFirst() {
        let entries = [
            DictionaryEntry(text: "New York City", aliases: ["new york city"]),
            DictionaryEntry(text: "New York", aliases: ["new york"]),
        ]
        let result = DictionaryCorrector.apply("I live in new york city", using: entries)
        XCTAssertEqual(result, "I live in New York City")
    }

    func testNoChangesNeeded() {
        let entries = [DictionaryEntry(text: "kubectl", aliases: ["cube cuddle"])]
        let input = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(DictionaryCorrector.apply(input, using: entries), input)
    }
}
