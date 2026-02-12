import CoreGraphics
import SwiftUI
import XCTest

@testable import Flux

final class SkillTests: XCTestCase {
    func testIconForNameMatchesKeywords() {
        XCTAssertEqual(Skill.iconForName("Browser Tools"), "globe")
        XCTAssertEqual(Skill.iconForName("Deploy Helper"), "arrow.up.circle.fill")
        XCTAssertEqual(Skill.iconForName("TestFlight Runner"), "checkmark.circle.fill")
        XCTAssertEqual(Skill.iconForName("Design Review"), "paintbrush.fill")
    }

    func testIconForNameFallsBackToSparkle() {
        XCTAssertEqual(Skill.iconForName("TotallyUnknown"), "sparkle")
    }

    func testColorForNameIsDeterministic() {
        let first = Skill.colorForName("Flux Skill")
        let second = Skill.colorForName("Flux Skill")
        XCTAssertEqual(first, second)
    }
}

final class SkillPermissionTests: XCTestCase {
    func testPermissionMetadata() {
        XCTAssertEqual(SkillPermission.automation.displayName, "Automation")
        XCTAssertEqual(SkillPermission.automation.description, "Control other apps via AppleScript")
        XCTAssertEqual(SkillPermission.automation.icon, "gearshape.2.fill")

        XCTAssertEqual(SkillPermission.screenRecording.displayName, "Screen Recording")
        XCTAssertEqual(SkillPermission.screenRecording.description, "Capture screenshots for context")
        XCTAssertEqual(SkillPermission.screenRecording.icon, "rectangle.inset.filled.and.person.filled")
    }
}

final class NotchGeometryTests: XCTestCase {
    func testNotchScreenRectAndHitTesting() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = CGRect(x: 0, y: 0, width: 200, height: 30)
        let geometry = NotchGeometry(deviceNotchRect: notch, screenRect: screen, windowHeight: 200, topInset: 10)

        let notchRect = geometry.notchScreenRect
        XCTAssertEqual(notchRect.origin.x, 400)
        XCTAssertEqual(notchRect.origin.y, 760)
        XCTAssertEqual(notchRect.size.width, 200)
        XCTAssertEqual(notchRect.size.height, 30)

        XCTAssertTrue(geometry.isPointInNotch(CGPoint(x: 395, y: 770)))
        XCTAssertFalse(geometry.isPointInNotch(CGPoint(x: 380, y: 770)))
    }

    func testOpenedPanelHitTesting() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let notch = CGRect(x: 0, y: 0, width: 200, height: 30)
        let geometry = NotchGeometry(deviceNotchRect: notch, screenRect: screen, windowHeight: 200, topInset: 10)
        let size = CGSize(width: 300, height: 200)

        let opened = geometry.openedScreenRect(for: size)
        XCTAssertEqual(opened.origin.x, 330)
        XCTAssertEqual(opened.origin.y, 570)
        XCTAssertEqual(opened.size.width, 340)
        XCTAssertEqual(opened.size.height, 220)

        XCTAssertTrue(geometry.isPointInOpenedPanel(CGPoint(x: 350, y: 600), size: size))
        XCTAssertTrue(geometry.isPointOutsidePanel(CGPoint(x: 100, y: 100), size: size))
    }
}

final class ChatTitleServiceTests: XCTestCase {
    func testTruncatedTitleShortensAndTrims() {
        let message = "   " + String(repeating: "a", count: 70) + "   "
        let title = ChatTitleService.truncatedTitle(from: message)
        XCTAssertTrue(title.hasSuffix("..."))
        XCTAssertEqual(title.count, 63)
    }

    func testTruncatedTitleLeavesShortMessage() {
        let message = "  Hello there  "
        let title = ChatTitleService.truncatedTitle(from: message)
        XCTAssertEqual(title, "Hello there")
    }
}

final class SkillCatalogTests: XCTestCase {
    func testRecommendedSkillsHaveUniqueIds() {
        let ids = SkillCatalog.recommended.map { $0.directoryName }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testRecommendedSkillsHaveDisplayNames() {
        XCTAssertTrue(SkillCatalog.recommended.allSatisfy { !$0.displayName.isEmpty })
    }
}

final class DictationEntryCodableTests: XCTestCase {
    func testDecodeLegacyEntryDefaultsStatusToSuccess() throws {
        let raw = """
        {
          "id": "E25DBBDA-B784-4CB3-8D3E-61BE4D2B4F6C",
          "rawTranscript": "hello world",
          "cleanedText": "Hello world",
          "finalText": "Hello world",
          "duration": 1.25,
          "timestamp": "2026-02-12T00:00:00Z",
          "targetApp": "Notes",
          "enhancementMethod": "none"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(raw.utf8)
        let entry = try decoder.decode(DictationEntry.self, from: data)

        XCTAssertEqual(entry.status, .success)
        XCTAssertNil(entry.failureReason)
    }

    func testEncodeDecodeFailureEntryRoundTrips() throws {
        let original = DictationEntry(
            rawTranscript: "",
            cleanedText: "",
            enhancedText: nil,
            finalText: "",
            duration: 2.0,
            timestamp: Date(timeIntervalSince1970: 1_760_000_000),
            targetApp: "TextEdit",
            enhancementMethod: .none,
            status: .failed,
            failureReason: "Timed out waiting for transcription result."
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DictationEntry.self, from: data)

        XCTAssertEqual(decoded.status, .failed)
        XCTAssertEqual(decoded.failureReason, "Timed out waiting for transcription result.")
    }
}
