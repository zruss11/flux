import Foundation

@Observable
@MainActor
final class CustomDictionaryStore {
    static let shared = CustomDictionaryStore()

    private(set) var entries: [DictionaryEntry] = []
    let maxEntries = 100
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/dictionary.json")
        load()
    }

    func add(_ entry: DictionaryEntry) {
        guard entries.count < maxEntries else { return }
        entries.append(entry)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.updatedAt = Date()
        entries[index] = updated
        save()
    }

    func remove(id: UUID) {
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
            print("Failed to load custom dictionary: \(error)")
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
            print("Failed to save custom dictionary: \(error)")
        }
    }
}
