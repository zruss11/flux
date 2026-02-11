import Foundation

@Observable
@MainActor
final class DictationHistoryStore {
    private(set) var entries: [DictationEntry] = []
    private let maxEntries = 500
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/dictation/history.json")
        load()
    }

    func add(_ entry: DictationEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        entries = []
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DictationEntry].self, from: data)
            entries.sort { $0.timestamp > $1.timestamp }
        } catch {
            print("Failed to load dictation history: \(error)")
            entries = []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save dictation history: \(error)")
        }
    }
}
