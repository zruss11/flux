import Foundation
import XCTest

@testable import Flux

final class MeetingStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flux-meetings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        MeetingStore.overrideMeetingsDirectory = tempDirectory
    }

    override func tearDownWithError() throws {
        MeetingStore.overrideMeetingsDirectory = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testCreateMeetingAndMoveToFolder() {
        let store = MeetingStore()

        let meeting = store.createMeeting(title: "Weekly Sync")
        XCTAssertEqual(store.summaries.count, 1)
        XCTAssertEqual(store.summaries.first?.title, "Weekly Sync")

        let utterance = MeetingUtterance(
            speakerIndex: 0,
            startTime: 0,
            endTime: 1.2,
            text: "Project status update"
        )
        store.appendUtterance(utterance, to: meeting.id)

        let folder = store.createFolder(name: "Engineering")
        XCTAssertNotNil(folder)

        if let folder {
            store.moveMeeting(meeting.id, toFolder: folder.id)
            XCTAssertEqual(store.summaries.first?.folderId, folder.id)
            XCTAssertEqual(store.summaries(forFolder: folder.id).count, 1)
        }
    }

    @MainActor
    func testDeleteFolderMovesMeetingsToUnfiled() {
        let store = MeetingStore()
        let meeting = store.createMeeting(title: "Design Review")
        let folder = store.createFolder(name: "Product")
        XCTAssertNotNil(folder)

        guard let folder else {
            XCTFail("Folder should exist")
            return
        }

        store.moveMeeting(meeting.id, toFolder: folder.id)
        XCTAssertEqual(store.summaries.first?.folderId, folder.id)

        store.deleteFolder(id: folder.id)
        XCTAssertNil(store.summaries.first?.folderId)
        XCTAssertTrue(store.folders.isEmpty)
    }
}

final class MeetingModelTests: XCTestCase {
    func testRTTMFormatting() {
        let meeting = Meeting(
            title: "RTTM",
            utterances: [
                MeetingUtterance(speakerIndex: 1, startTime: 1.0, endTime: 2.5, text: "Hello")
            ]
        )

        XCTAssertTrue(meeting.rttmText.contains("speaker_1"))
        XCTAssertTrue(meeting.rttmText.contains("SPEAKER meeting 1"))
    }
}

final class MeetingTranscriptionPipelineTests: XCTestCase {
    @MainActor
    func testFallbackUtteranceWithoutPCMData() async {
        let pipeline = MeetingTranscriptionPipeline.shared
        let utterances = await pipeline.utterances(
            from: "Hello team, let's start.",
            duration: 4.5,
            pcmData: nil
        )

        XCTAssertEqual(utterances.count, 1)
        XCTAssertEqual(utterances.first?.speakerIndex, 0)
        XCTAssertEqual(utterances.first?.text, "Hello team, let's start.")
        XCTAssertEqual(utterances.first?.startTime, 0)
        XCTAssertEqual(utterances.first?.endTime, 4.5)
    }

    @MainActor
    func testFallbackIgnoresBlankTranscript() async {
        let pipeline = MeetingTranscriptionPipeline.shared
        let utterances = await pipeline.utterances(
            from: "   ",
            duration: 3.0,
            pcmData: nil
        )

        XCTAssertTrue(utterances.isEmpty)
    }
}
