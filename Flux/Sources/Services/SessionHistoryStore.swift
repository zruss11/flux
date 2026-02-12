import Foundation

@Observable
@MainActor
final class SessionHistoryStore {
    private(set) var sessions: [AppSession] = []
    private let maxSessions = 200
    private let fileURL: URL
    private var saveTimer: Timer?

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/sessions/history.json")
        load()
    }

    func record(_ session: AppSession) {
        // Filter out accidental app switches (< 2 seconds)
        if let duration = session.durationSeconds, duration < 2.0 { return }

        sessions.insert(session, at: 0)
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }
        debouncedSave()
    }

    func recentSessions(appName: String? = nil, limit: Int = 20) -> [AppSession] {
        let filtered = appName.map { name in
            sessions.filter { $0.appName.localizedCaseInsensitiveContains(name) }
        } ?? sessions
        return Array(filtered.prefix(limit))
    }

    func contextSummaryText(limit: Int = 10) -> String {
        let recent = Array(sessions.prefix(limit))
        if recent.isEmpty { return "No recent app activity recorded." }

        let formatter = RelativeDateTimeFormatter()
        return recent.map { session in
            let app = session.appName
            let window = session.windowTitle.map { " - \($0)" } ?? ""
            let time = formatter.localizedString(for: session.startedAt, relativeTo: Date())
            let summary = session.contextSummary.map { "\n  Context: \($0)" } ?? ""
            return "[\(time)] \(app)\(window)\(summary)"
        }.joined(separator: "\n")
    }

    func clearAll() {
        sessions = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = try decoder.decode([AppSession].self, from: data)
            sessions.sort { $0.startedAt > $1.startedAt }
        } catch {
            print("Failed to load session history: \(error)")
            sessions = []
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
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save session history: \(error)")
        }
    }

    private func debouncedSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.save()
            }
        }
    }
}
