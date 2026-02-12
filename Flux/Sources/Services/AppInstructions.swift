import Foundation

/// Model and persistence for per-app custom AI instructions.
///
/// Allows users to define different AI behavior based on which app is in the foreground.
/// For example: "In Slack, be casual and use emoji" or "In Xcode, be technical and precise."
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
        if let index = instructions.firstIndex(where: { $0.bundleId == instruction.bundleId }) {
            instructions[index] = instruction
        } else {
            instructions.append(instruction)
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
        instructions = (try? JSONDecoder().decode([Instruction].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(instructions) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
