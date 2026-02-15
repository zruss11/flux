import XCTest

@testable import Flux

final class ParakeetTokenizerTests: XCTestCase {

    // MARK: - Vocabulary

    private func makeTokenizer(vocab: [Int: String] = [:]) -> ParakeetTokenizer {
        ParakeetTokenizer(vocabulary: vocab)
    }

    private let sampleVocab: [Int: String] = [
        0: "<blank>",
        1: "▁Hello",
        2: "▁world",
        3: "▁this",
        4: "▁is",
        5: "▁a",
        6: "▁test",
        7: "ing",
        8: "▁the",
        9: "▁quick",
        10: "▁brown",
        11: "▁fox",
    ]

    // MARK: - RNNT Decoding

    func testDecodeRNNTBasic() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        let result = tokenizer.decodeRNNT([1, 2])
        XCTAssertEqual(result, "Hello world")
    }

    func testDecodeRNNTWithSubword() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        // "test" + "ing" continuation piece
        let result = tokenizer.decodeRNNT([6, 7])
        XCTAssertEqual(result, "testing")
    }

    func testDecodeRNNTSkipsBlanks() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        let result = tokenizer.decodeRNNT([0, 1, 0, 2, 0])
        XCTAssertEqual(result, "Hello world")
    }

    func testDecodeRNNTEmptyInput() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        XCTAssertEqual(tokenizer.decodeRNNT([]), "")
    }

    func testDecodeRNNTUnknownTokensSkipped() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        let result = tokenizer.decodeRNNT([1, 999, 2])
        XCTAssertEqual(result, "Hello world")
    }

    // MARK: - CTC Decoding

    func testDecodeCTCDeduplication() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        // CTC: repeated tokens should be collapsed
        let result = tokenizer.decode([1, 1, 1, 0, 2, 2])
        XCTAssertEqual(result, "Hello world")
    }

    func testDecodeCTCWithBlanksAndRepeats() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        // Blank between same tokens allows reappearance
        let result = tokenizer.decode([1, 0, 1, 2])
        XCTAssertEqual(result, "Hello Hello world")
    }

    // MARK: - Word Assembly

    func testWordBoundaryHandling() {
        let vocab: [Int: String] = [
            0: "<blank>",
            1: "▁I",
            2: "▁like",
            3: "▁co",
            4: "ff",
            5: "ee",
        ]
        let tokenizer = makeTokenizer(vocab: vocab)
        let result = tokenizer.decodeRNNT([1, 2, 3, 4, 5])
        XCTAssertEqual(result, "I like coffee")
    }

    func testFullSentence() {
        let tokenizer = makeTokenizer(vocab: sampleVocab)
        let result = tokenizer.decodeRNNT([8, 9, 10, 11])
        XCTAssertEqual(result, "the quick brown fox")
    }
}
