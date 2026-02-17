import Foundation

@Observable
@MainActor
final class MeetingStore {
    static let shared = MeetingStore()

    /// Test-only override for meetings persistence location.
    nonisolated(unsafe) static var overrideMeetingsDirectory: URL?

    private(set) var summaries: [MeetingSummary] = []
    private(set) var folders: [MeetingFolder] = []

    private var meetingsById: [UUID: Meeting] = [:]

    private static nonisolated var meetingsDirectory: URL {
        if let overrideMeetingsDirectory {
            return overrideMeetingsDirectory
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/meetings", isDirectory: true)
    }

    private static nonisolated var meetingFilesDirectory: URL {
        meetingsDirectory.appendingPathComponent("items", isDirectory: true)
    }

    private static nonisolated var indexURL: URL {
        meetingsDirectory.appendingPathComponent("index.json")
    }

    init() {
        loadIndex()
    }

    // MARK: - Meeting lifecycle

    @discardableResult
    func createMeeting(title: String? = nil) -> Meeting {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = trimmedTitle.isEmpty
            ? "Meeting \(dateFormatter.string(from: now))"
            : trimmedTitle

        let meeting = Meeting(
            title: resolvedTitle,
            startedAt: now,
            status: .recording
        )

        meetingsById[meeting.id] = meeting
        summaries.insert(MeetingSummary(from: meeting), at: 0)
        saveMeeting(meeting)
        saveIndex()
        return meeting
    }

    func appendUtterance(_ utterance: MeetingUtterance, to meetingId: UUID) {
        guard var meeting = meeting(id: meetingId) else { return }
        meeting.utterances.append(utterance)
        updateMeeting(meeting)
    }

    func finishMeeting(id meetingId: UUID, status: MeetingStatus = .completed) {
        guard var meeting = meeting(id: meetingId) else { return }
        meeting.status = status
        meeting.endedAt = Date()
        updateMeeting(meeting)
    }

    func markMeetingFailed(id meetingId: UUID) {
        finishMeeting(id: meetingId, status: .failed)
    }

    func updateMeeting(_ meeting: Meeting) {
        meetingsById[meeting.id] = meeting
        let summary = MeetingSummary(from: meeting)

        if let index = summaries.firstIndex(where: { $0.id == meeting.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }

        summaries.sort { $0.updatedAt > $1.updatedAt }
        saveMeeting(meeting)
        saveIndex()
    }

    func deleteMeeting(id meetingId: UUID) {
        meetingsById.removeValue(forKey: meetingId)
        summaries.removeAll { $0.id == meetingId }

        for index in folders.indices {
            folders[index].meetingIds.removeAll { $0 == meetingId }
        }

        let fileURL = Self.meetingFilesDirectory.appendingPathComponent("\(meetingId.uuidString).json")
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        saveIndex()
    }

    func meeting(id: UUID) -> Meeting? {
        if let inMemory = meetingsById[id] {
            return inMemory
        }

        let url = Self.meetingFilesDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let meeting = try? decoder.decode(Meeting.self, from: data) else { return nil }

        meetingsById[id] = meeting
        return meeting
    }

    // MARK: - Folder management

    @discardableResult
    func createFolder(name: String) -> MeetingFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folder = MeetingFolder(name: trimmed)
        folders.append(folder)
        saveIndex()
        return folder
    }

    func renameFolder(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }

        folders[index].name = trimmed
        saveIndex()
    }

    func deleteFolder(id: UUID) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == id }) else { return }

        let meetingIds = folders[folderIndex].meetingIds
        for meetingId in meetingIds {
            moveMeeting(meetingId, toFolder: nil)
        }

        folders.remove(at: folderIndex)
        saveIndex()
    }

    func moveMeeting(_ meetingId: UUID, toFolder folderId: UUID?) {
        for index in folders.indices {
            folders[index].meetingIds.removeAll { $0 == meetingId }
        }

        if let folderId,
           let folderIndex = folders.firstIndex(where: { $0.id == folderId }) {
            if !folders[folderIndex].meetingIds.contains(meetingId) {
                folders[folderIndex].meetingIds.append(meetingId)
            }
        }

        guard var meeting = meeting(id: meetingId) else {
            saveIndex()
            return
        }

        meeting.folderId = folderId
        updateMeeting(meeting)
    }

    // MARK: - Queries

    var unfiledSummaries: [MeetingSummary] {
        summaries
            .filter { $0.folderId == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func summaries(forFolder folderId: UUID) -> [MeetingSummary] {
        guard let folder = folders.first(where: { $0.id == folderId }) else { return [] }

        return folder.meetingIds.compactMap { meetingId in
            summaries.first(where: { $0.id == meetingId })
        }
    }

    func clearAll() {
        summaries = []
        folders = []
        meetingsById = [:]

        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: Self.meetingsDirectory)
        }
    }

    // MARK: - Persistence

    private struct IndexFile: Codable {
        var summaries: [MeetingSummary]
        var folders: [MeetingFolder]
    }

    private static nonisolated func ensureDirectories() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: meetingFilesDirectory, withIntermediateDirectories: true)
    }

    private func saveMeeting(_ meeting: Meeting) {
        let snapshot = meeting
        Task.detached(priority: .background) {
            Self.ensureDirectories()

            let url = Self.meetingFilesDirectory.appendingPathComponent("\(snapshot.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func saveIndex() {
        let summariesSnapshot = summaries
        let foldersSnapshot = folders

        Task.detached(priority: .background) {
            Self.ensureDirectories()

            let index = IndexFile(summaries: summariesSnapshot, folders: foldersSnapshot)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            if let data = try? encoder.encode(index) {
                try? data.write(to: Self.indexURL, options: .atomic)
            }
        }
    }

    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: Self.indexURL.path) else {
            summaries = []
            folders = []
            return
        }

        guard let data = try? Data(contentsOf: Self.indexURL) else {
            summaries = []
            folders = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let index = try? decoder.decode(IndexFile.self, from: data) else {
            summaries = []
            folders = []
            return
        }

        summaries = index.summaries.sorted { $0.updatedAt > $1.updatedAt }
        folders = index.folders
    }
}
