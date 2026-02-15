import XCTest
@testable import Flux

final class WakeWordDetectorTests: XCTestCase {

    // MARK: - State

    @MainActor
    func testIsEnabledReturnsFalseWhenIdle() {
        let detector = WakeWordDetector.shared
        // The shared detector starts in .idle, and without calling start()
        // it should remain idle.
        XCTAssertFalse(detector.isEnabled)
    }

    // MARK: - Configuration Defaults

    @MainActor
    func testWakePhraseDefault() {
        // Clear any stored override so the default kicks in.
        UserDefaults.standard.removeObject(forKey: "wakePhrase")
        let detector = WakeWordDetector.shared
        XCTAssertEqual(detector.wakePhrase, "Hey Flux")
    }

    @MainActor
    func testSilenceTimeoutClamping() {
        // When no value is stored (0.0), the default should be 1.5.
        UserDefaults.standard.removeObject(forKey: "handsFreesilenceTimeout")
        let detector = WakeWordDetector.shared
        XCTAssertEqual(detector.silenceTimeout, 1.5, accuracy: 0.01)

        // Values below the lower bound should clamp to 0.5.
        UserDefaults.standard.set(0.1, forKey: "handsFreesilenceTimeout")
        XCTAssertEqual(detector.silenceTimeout, 0.5, accuracy: 0.01)

        // Values above the upper bound should clamp to 5.0.
        UserDefaults.standard.set(99.0, forKey: "handsFreesilenceTimeout")
        XCTAssertEqual(detector.silenceTimeout, 5.0, accuracy: 0.01)

        // Valid values should pass through.
        UserDefaults.standard.set(2.5, forKey: "handsFreesilenceTimeout")
        XCTAssertEqual(detector.silenceTimeout, 2.5, accuracy: 0.01)

        // Clean up.
        UserDefaults.standard.removeObject(forKey: "handsFreesilenceTimeout")
    }

    @MainActor
    func testWakePhraseReadsCustomValue() {
        UserDefaults.standard.set("OK Computer", forKey: "wakePhrase")
        let detector = WakeWordDetector.shared
        XCTAssertEqual(detector.wakePhrase, "OK Computer")

        // Clean up.
        UserDefaults.standard.removeObject(forKey: "wakePhrase")
    }
}
