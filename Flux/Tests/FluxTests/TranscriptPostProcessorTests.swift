import Testing
@testable import Flux

struct TranscriptPostProcessorTests {

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
}
