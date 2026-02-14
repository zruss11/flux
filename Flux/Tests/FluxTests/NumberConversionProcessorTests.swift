import Testing
@testable import Flux

struct NumberConversionProcessorTests {

    @Test func emptyStringPassesThrough() {
        #expect(NumberConversionProcessor.process("") == "")
    }

    @Test func noNumbersPassThrough() {
        let input = "hello world"
        #expect(NumberConversionProcessor.process(input) == input)
    }

    @Test func convertsSingleDigitWords() {
        #expect(NumberConversionProcessor.process("I have five apples") == "I have 5 apples")
    }

    @Test func convertsTeens() {
        #expect(NumberConversionProcessor.process("there are thirteen items") == "there are 13 items")
    }

    @Test func convertsTens() {
        #expect(NumberConversionProcessor.process("twenty three people") == "23 people")
    }

    @Test func convertsHundreds() {
        #expect(NumberConversionProcessor.process("one hundred items") == "100 items")
    }

    @Test func convertsThousands() {
        #expect(NumberConversionProcessor.process("one thousand two hundred") == "1200")
    }

    @Test func convertsOrdinals() {
        #expect(NumberConversionProcessor.process("the first item") == "the 1st item")
        #expect(NumberConversionProcessor.process("the third row") == "the 3rd row")
    }

    @Test func preservesPunctuation() {
        let input = "I need five."
        let result = NumberConversionProcessor.process(input)
        #expect(result == "I need 5.")
    }

    @Test func preservesNonNumberWords() {
        let input = "the quick brown fox"
        #expect(NumberConversionProcessor.process(input) == input)
    }
}
