import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationModelsClientError: Error {
    case unavailable
}

/// Thin wrapper around Apple's Foundation Models APIs so it's easy to reuse for one-off prompts.
actor FoundationModelsClient {
    static let shared = FoundationModelsClient()
    private init() {}

    nonisolated var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    func completeText(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw FoundationModelsClientError.unavailable
            }

            // Default local model selection; keep this as a single call-site for future expansion.
            let session = LanguageModelSession()
            let prompt = """
            \(system)

            User:
            \(user)
            """

            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif

        throw FoundationModelsClientError.unavailable
    }
}
