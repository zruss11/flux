import Testing
@testable import Flux

struct IntentCorrectionProcessorTests {

    @Test func emptyStringPassesThrough() {
        #expect(IntentCorrectionProcessor.process("") == "")
    }

    @Test func noTriggerPassesThrough() {
        let input = "send the email to John"
        #expect(IntentCorrectionProcessor.process(input) == input)
    }

    @Test func correctsWithWait() {
        let input = "use the old API, wait, use the new API"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Use the new API")
    }

    @Test func correctsWithNo() {
        let input = "send it to John, no, send it to Sarah"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Send it to Sarah")
    }

    @Test func correctsWithScratchThat() {
        let input = "open the file scratch that close the window"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Close the window")
    }

    @Test func correctsWithActually() {
        let input = "delete the file actually rename it"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Rename it")
    }

    @Test func handlesTriggerAtEnd() {
        let input = "send the email, wait"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "Send the email")
    }

    @Test func preservesSentenceBeforePeriod() {
        let input = "First sentence. Second part, no, corrected part"
        let result = IntentCorrectionProcessor.process(input)
        #expect(result == "First sentence. Corrected part")
    }
}
