import XCTest

@testable import Flux

final class ASRPostProcessorTests: XCTestCase {

    // MARK: - Fragment Repair

    func testRepairsStutter() {
        let input = "I wan- want to go"
        let result = ASRPostProcessor.repairFragments(input)
        XCTAssertEqual(result, "I want to go")
    }

    func testRepairsWordFragment() {
        let input = "the app- application is great"
        let result = ASRPostProcessor.repairFragments(input)
        XCTAssertEqual(result, "the application is great")
    }

    func testNoFragmentNoChange() {
        let input = "this is a normal sentence"
        XCTAssertEqual(ASRPostProcessor.repairFragments(input), input)
    }

    // MARK: - Intent Correction

    func testCorrectsSelfCorrectionWithActually() {
        let input = "use the old API, wait, actually use the new API"
        let result = ASRPostProcessor.correctIntent(input)
        XCTAssertEqual(result, "use the new API")
    }

    func testCorrectsSelfCorrectionWithIMean() {
        let input = "send it to John, I mean send it to Jane"
        let result = ASRPostProcessor.correctIntent(input)
        XCTAssertEqual(result, "send it to Jane")
    }

    func testNoSelfCorrection() {
        let input = "please send the email"
        XCTAssertEqual(ASRPostProcessor.correctIntent(input), input)
    }

    // MARK: - Repeat Removal

    func testRemovesRepeatedPhrase() {
        let input = "send the update send the update"
        let result = ASRPostProcessor.removeRepeatedPhrases(input)
        XCTAssertEqual(result, "send the update")
    }

    func testNoRepeatsNoChange() {
        let input = "send the update to production"
        XCTAssertEqual(ASRPostProcessor.removeRepeatedPhrases(input), input)
    }

    // MARK: - Number Conversion

    func testConvertsTwoWordNumber() {
        let input = "I have forty two items"
        let result = ASRPostProcessor.convertNumbers(input)
        XCTAssertEqual(result, "I have 42 items")
    }

    func testConvertsHundreds() {
        let input = "there are one hundred twenty three results"
        let result = ASRPostProcessor.convertNumbers(input)
        XCTAssertEqual(result, "there are 123 results")
    }

    func testConvertsThousands() {
        let input = "the price is one thousand two hundred dollars"
        let result = ASRPostProcessor.convertNumbers(input)
        XCTAssertEqual(result, "the price is 1,200 dollars")
    }

    func testSingleNumberWordNotConverted() {
        // Single number words (one word only) should NOT be converted.
        let input = "I have one apple"
        let result = ASRPostProcessor.convertNumbers(input)
        XCTAssertEqual(result, "I have one apple")
    }

    // MARK: - Full Pipeline

    func testFullPipelineAllStages() {
        let config = ASRPostProcessor.Config.allEnabled
        let input = "I wan- want to send send the update"
        let result = ASRPostProcessor.process(input, config: config)
        XCTAssertEqual(result, "I want to send the update")
    }

    func testFullPipelineEmptyString() {
        XCTAssertEqual(ASRPostProcessor.process(""), "")
    }

    func testFullPipelineNoChangesNeeded() {
        let input = "The quick brown fox jumps over the lazy dog"
        let result = ASRPostProcessor.process(input, config: .allEnabled)
        XCTAssertEqual(result, input)
    }

    func testDisabledStagesAreSkipped() {
        let config = ASRPostProcessor.Config(
            enableFragmentRepair: false,
            enableIntentCorrection: false,
            enableRepeatRemoval: false,
            enableNumberConversion: false
        )
        let input = "I wan- want forty two items"
        let result = ASRPostProcessor.process(input, config: config)
        // Only whitespace normalization should apply, no stage transformations.
        XCTAssertEqual(result, "I wan- want forty two items")
    }
}
