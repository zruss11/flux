import Foundation

struct TelegramPairingRequest: Identifiable, Codable {
    let chatId: String
    let code: String
    let createdAt: Double
    let username: String?
    let firstName: String?
    let lastName: String?

    var id: String { chatId }
}

struct TelegramPairingApproval: Codable {
    let approvedAt: Double
}

struct TelegramPairingState: Codable {
    var pending: [String: TelegramPairingRequest]
    var approved: [String: TelegramPairingApproval]

    static var empty: TelegramPairingState {
        TelegramPairingState(pending: [:], approved: [:])
    }
}

enum TelegramPairingStore {
    private static let ttlSeconds: Double = 3600

    static func loadPending() -> [TelegramPairingRequest] {
        var state = load()
        pruneExpired(in: &state)
        save(state)
        return state.pending.values.sorted { $0.createdAt > $1.createdAt }
    }

    static func approve(code: String) -> TelegramPairingRequest? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }

        var state = load()
        pruneExpired(in: &state)

        if let match = state.pending.values.first(where: { $0.code.uppercased() == normalized }) {
            state.pending.removeValue(forKey: match.chatId)
            state.approved[match.chatId] = TelegramPairingApproval(approvedAt: Date().timeIntervalSince1970)
            save(state)
            return match
        }

        save(state)
        return nil
    }

    static func removePending(chatId: String) {
        var state = load()
        state.pending.removeValue(forKey: chatId)
        save(state)
    }

    private static func pruneExpired(in state: inout TelegramPairingState) {
        let now = Date().timeIntervalSince1970
        let expired = state.pending.filter { now - $0.value.createdAt > ttlSeconds }.map(\.key)
        for key in expired {
            state.pending.removeValue(forKey: key)
        }
    }

    private static func load() -> TelegramPairingState {
        let url = pairingFileURL()
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(TelegramPairingState.self, from: data)) ?? .empty
    }

    private static func save(_ state: TelegramPairingState) {
        let url = pairingFileURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }

        let tmpURL = dir.appendingPathComponent("pairing.json.tmp")
        try? data.write(to: tmpURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try? FileManager.default.moveItem(at: tmpURL, to: url)
        }
    }

    private static func pairingFileURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flux/telegram", isDirectory: true)
        return dir.appendingPathComponent("pairing.json")
    }
}
