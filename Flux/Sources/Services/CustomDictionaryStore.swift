import Foundation
import os

/// Thread-safe observable store for custom dictionary entries.
@Observable
final class CustomDictionaryStore: @unchecked Sendable {
    static let shared = CustomDictionaryStore()

    private(set) var entries: [DictionaryEntry] = []
    let maxEntries = 100
    private let fileURL: URL
    private let lock = NSLock()

    private init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/dictionary.json")
        load()
    }

    /// Thread-safe read access to entries.
    nonisolated
    func getEntries() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func add(_ entry: DictionaryEntry) {
        lock.lock()
        defer { lock.unlock() }
        guard entries.count < maxEntries else { return }
        entries.append(entry)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        entries[index] = updated
        save()
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id }
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
            entries = try decoder.decode([DictionaryEntry].self, from: data)
        } catch {
            Log.app.error("Failed to load custom dictionary: \(error)")
            entries = []
        }
    }

    private func save() {
        // Capture entries on background queue to avoid blocking.
        let entriesToSave = getEntries()
        Task.detached(priority: .background) { [fileURL] in
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
                let data = try encoder.encode(entriesToSave)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.app.error("Failed to save custom dictionary: \(error)")
            }
        }
    }
}
