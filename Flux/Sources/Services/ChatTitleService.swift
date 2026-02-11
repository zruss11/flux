import Foundation

actor ChatTitleService {
    static let shared = ChatTitleService()
    private init() {}

    func proposeTitle(fromFirstUserMessage message: String) async -> String? {
        let creator = selectedCreator()
        switch creator {
        case .firstUserMessage:
            return ChatTitleService.truncatedTitle(from: message)
        case .foundationModels:
            return await proposeFoundationModelsTitle(fromFirstUserMessage: message)
        }
    }

    static func truncatedTitle(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(trimmed.prefix(60))
        return truncated.count < trimmed.count ? truncated + "..." : truncated
    }

    nonisolated private func selectedCreator() -> ChatTitleCreator {
        let raw = UserDefaults.standard.string(forKey: "chatTitleCreator") ?? ChatTitleCreator.foundationModels.rawValue
        return ChatTitleCreator(rawValue: raw) ?? .foundationModels
    }

    private func proposeFoundationModelsTitle(fromFirstUserMessage message: String) async -> String? {
        guard FoundationModelsClient.shared.isAvailable else { return nil }

        let system = """
        You are a title generator for a chat app.
        Return a short, specific title (3-7 words). No quotes. No trailing punctuation.
        """
        let user = """
        Generate a title for this first user message:
        \(message)
        """

        do {
            let raw = try await FoundationModelsClient.shared.completeText(system: system, user: user)
            let cleaned = ChatTitleService.cleanTitle(raw)

            guard !cleaned.isEmpty else { return nil }
            return String(cleaned.prefix(80))
        } catch {
            return nil
        }
    }

    private static func cleanTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.split(separator: " ").joined(separator: " ")

        // Strip common wrappers like `Title: ...` or quotes.
        let lower = s.lowercased()
        if lower.hasPrefix("title:") {
            s = String(s.dropFirst("title:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("chat title:") {
            s = String(s.dropFirst("chat title:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Titles look better without trailing punctuation.
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-"))

        return s
    }
}
