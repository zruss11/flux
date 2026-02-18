import Foundation

@MainActor
final class MeetingExportService {
    static let shared = MeetingExportService()

    private init() {}

    func exportTranscriptTXT(for meeting: Meeting, to url: URL) throws {
        try meeting.transcriptText.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportRTTM(for meeting: Meeting, to url: URL) throws {
        try meeting.rttmText.write(to: url, atomically: true, encoding: .utf8)
    }
}
