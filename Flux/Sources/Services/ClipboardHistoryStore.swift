import Foundation

@Observable
@MainActor
final class ClipboardHistoryStore {
    private(set) var entries: [ClipboardEntry] = []
    private let maxEntries = 10
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/clipboard/history.json")
        load()
    }

    func add(_ entry: ClipboardEntry) {
        if let last = entries.first, last.content == entry.content {
            return
        }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
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
            entries = try decoder.decode([ClipboardEntry].self, from: data)
            entries.sort { $0.timestamp > $1.timestamp }
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
        } catch {
            Log.clipboard.error("Failed to load clipboard history: \(error)")
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
            Log.clipboard.error("Failed to save clipboard history: \(error)")
        }
    }
}
