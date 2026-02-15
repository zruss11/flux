import Testing
@testable import Flux

struct FragmentRepairProcessorTests {

    @Test func emptyStringPassesThrough() {
        #expect(FragmentRepairProcessor.process("") == "")
    }

    @Test func noFragmentsPassThrough() {
        let input = "I want to go to the store"
        #expect(FragmentRepairProcessor.process(input) == input)
    }

    @Test func repairsRepeatedWordFragment() {
        // "wan- want" should collapse to "want"
        let input = "I wan- want to go"
        let result = FragmentRepairProcessor.process(input)
        #expect(result == "I want to go")
    }

    @Test func removesOrphanShortFragment() {
        // Short orphan fragment (< 6 chars before dash) gets removed
        let input = "the abso- thing is great"
        let result = FragmentRepairProcessor.process(input)
        #expect(result == "the thing is great")
    }

    @Test func preservesLegitimateHyphenatedWords() {
        // Long words with hyphens should not be stripped
        let input = "this is a well-known fact"
        let result = FragmentRepairProcessor.process(input)
        #expect(result.contains("well-known"))
    }

    @Test func collapsesMultipleSpaces() {
        let input = "hello   world"
        let result = FragmentRepairProcessor.process(input)
        #expect(!result.contains("  "))
    }
}
