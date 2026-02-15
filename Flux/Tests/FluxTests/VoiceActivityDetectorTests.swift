import XCTest
@testable import Flux

final class VoiceActivityDetectorTests: XCTestCase {

    @MainActor
    func testStopMonitoringCleansUp() {
        let vad = VoiceActivityDetector()

        // Start monitoring with a real meter.
        let meter = AudioLevelMeter()
        vad.startMonitoring(
            meter: meter,
            silenceThreshold: 0.01,
            silenceDuration: 1.0
        ) {
            XCTFail("onSilence should not fire after stopMonitoring")
        }

        // Stop should clean up without crashing.
        vad.stopMonitoring()

        // Calling stop again should be a no-op.
        vad.stopMonitoring()
    }

    @MainActor
    func testStartMonitoringReplacesExisting() {
        let vad = VoiceActivityDetector()
        let meter = AudioLevelMeter()

        var firstCallbackCalled = false
        vad.startMonitoring(
            meter: meter,
            silenceThreshold: 0.01,
            silenceDuration: 1.0
        ) {
            firstCallbackCalled = true
        }

        // Starting again should replace the previous session.
        var secondCallbackCalled = false
        vad.startMonitoring(
            meter: meter,
            silenceThreshold: 0.02,
            silenceDuration: 2.0
        ) {
            secondCallbackCalled = true
        }

        // Clean up.
        vad.stopMonitoring()

        // Neither callback should have fired (no silence detected in this brief window).
        XCTAssertFalse(firstCallbackCalled)
        XCTAssertFalse(secondCallbackCalled)
    }
}
