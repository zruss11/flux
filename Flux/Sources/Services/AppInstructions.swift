import Foundation

/// Model and persistence for per-app dictation enhancement instructions.
///
/// Allows users to define different dictation rewrite behavior based on which app is in the foreground.
/// For example: "In Slack, keep it casual" or "In Xcode, make it technical and precise."
///
/// Instructions are stored as a JSON array in UserDefaults under `appInstructions`.
@MainActor
final class AppInstructions {
    static let shared = AppInstructions()

    struct Instruction: Codable, Identifiable, Equatable {
        let id: String          // UUID string
        var bundleId: String    // e.g. "com.tinyspeck.slackmacgap"
        var appName: String     // e.g. "Slack"
        var instruction: String // e.g. "Be casual, use emoji"

        init(bundleId: String, appName: String, instruction: String, id: String = UUID().uuidString) {
            self.id = id
            self.bundleId = bundleId
            self.appName = appName
            self.instruction = instruction
        }
    }

    private static let storageKey = "appInstructions"

    /// All saved per-app instructions.
    private(set) var instructions: [Instruction] = []

    private init() {
        load()
    }

    /// Find the instruction matching a given bundle identifier (if any).
    func instruction(forBundleId bundleId: String) -> Instruction? {
        instructions.first { $0.bundleId == bundleId }
    }

    /// Add or update an instruction. If an instruction with the same `bundleId` exists, it is replaced.
    func upsert(_ instruction: Instruction) {
        let trimmedBundleId = instruction.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBundleId.isEmpty else { return }

        let trimmedAppName = instruction.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else { return }

        var updated = instruction
        updated.bundleId = trimmedBundleId
        updated.appName = trimmedAppName.isEmpty ? trimmedBundleId : trimmedAppName
        updated.instruction = trimmedInstruction

        if let index = instructions.firstIndex(where: { $0.bundleId == updated.bundleId }) {
            instructions[index] = updated
        } else {
            instructions.append(updated)
        }
        save()
    }

    /// Remove the instruction at the given index.
    func remove(at index: Int) {
        guard instructions.indices.contains(index) else { return }
        instructions.remove(at: index)
        save()
    }

    /// Remove the instruction matching the given id.
    func remove(id: String) {
        instructions.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([Instruction].self, from: data) {
            instructions = decoded
            return
        }

        instructions = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(instructions)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            Log.appMonitor.error("Failed to save app instructions: \(error)")
        }
        NotificationCenter.default.post(name: .appInstructionsDidChange, object: nil)
    }
}
