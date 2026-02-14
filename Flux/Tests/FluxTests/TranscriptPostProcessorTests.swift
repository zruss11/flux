import Foundation
import Testing
@testable import Flux

struct TranscriptPostProcessorTests {

    init() {
        // Ensure pipeline defaults are registered so stages are enabled.
        TranscriptPostProcessor.registerDefaults()
    }

    @Test @MainActor func emptyStringPassesThrough() {
        #expect(TranscriptPostProcessor.process("") == "")
    }

    @Test @MainActor func whitespaceOnlyPassesThrough() {
        #expect(TranscriptPostProcessor.process("   ") == "   ")
    }

    @Test @MainActor func fullPipelineCleansDictatedText() {
        // Simulates: fillers + self-correction + numbers
        let input = "um send twenty three emails, wait, send five emails"
        let result = TranscriptPostProcessor.process(input)
        // After filler removal: "send twenty three emails, wait, send five emails"
        // After intent correction: "send five emails" (or "Send five emails")
        // After number conversion: "Send 5 emails"
        #expect(result == "Send 5 emails")
    }

    @Test @MainActor func pipelineHandlesCleanInput() {
        let input = "Hello world"
        let result = TranscriptPostProcessor.process(input)
        #expect(result == "Hello world")
    }

    // MARK: - Stage Interaction Tests

    @Test @MainActor func numberConversionAfterIntentCorrection() {
        let input = "send twenty emails, no, send five emails"
        let result = TranscriptPostProcessor.process(input)
        #expect(result == "Send 5 emails")
    }

    @Test @MainActor func fragmentRepairWithCorrection() {
        let input = "wan- want to use API v1, wait, use API v2"
        let result = TranscriptPostProcessor.process(input)
        #expect(result == "Use API v2")
    }

    @Test @MainActor func fullPipelineComplex() {
        let input = "um I wan- want twenty three items, scratch that, I need five items"
        let result = TranscriptPostProcessor.process(input)
        #expect(result == "I need 5 items")
    }

    // MARK: - Intent Correction Word Boundary Tests

    @Test @MainActor func waitDoesNotMatchInsideAwaiting() {
        // "wait" should NOT trigger inside "awaiting"
        let input = "I am awaiting the results"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "I am awaiting the results")
    }

    @Test @MainActor func iMeanTriggerMatches() {
        // "i mean" should work now that triggers are lowercased
        let input = "use the old one, I mean use the new one"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Use the new one")
    }

    @Test @MainActor func chainedCorrectionsWithActually() {
        let input = "open file A, actually open file B, actually open file C"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Open file C")
    }

    // MARK: - Number Conversion Edge Cases

    @Test func zeroHundredIsInvalid() {
        // "zero hundred" should not convert to 100
        let input = "zero hundred"
        let result = NumberConversionProcessor.process(input)
        #expect(result == "zero hundred")
    }

    @Test func zeroAloneConvertsToDigit() {
        let input = "the count is zero"
        let result = NumberConversionProcessor.process(input)
        #expect(result == "the count is 0")
    }

    @Test func complexNumberConversion() {
        let input = "two thousand three hundred forty five"
        let result = NumberConversionProcessor.process(input)
        #expect(result == "2345")
    }

    @Test func aHundredConverts() {
        let input = "a hundred items"
        let result = NumberConversionProcessor.process(input)
        #expect(result == "100 items")
    }

    @Test func aThousandConverts() {
        let input = "a thousand reasons"
        let result = NumberConversionProcessor.process(input)
        #expect(result == "1000 reasons")
    }

    // MARK: - Fragment Repair Edge Cases

    @Test func caseInsensitiveBackreference() {
        // "Wan- want" repairs via backreference; $1 captures original case "Wan"
        let input = "I Wan- want to go"
        let result = FragmentRepairProcessor.process(input)
        #expect(result == "I Want to go")
    }

    @Test func legitimateHyphenatedWordPreserved() {
        // "cross" is 5 chars, should NOT be stripped with threshold of 4
        let input = "the cross- examination was thorough"
        let result = FragmentRepairProcessor.process(input)
        #expect(result == "the cross- examination was thorough")
    }
}
