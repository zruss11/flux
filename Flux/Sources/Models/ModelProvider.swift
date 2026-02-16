import Foundation

struct ModelInfo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: String
    let reasoning: Bool
    let contextWindow: Int
    let maxTokens: Int

    var modelSpec: String { "\(provider):\(id)" }
}

struct ProviderInfo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    var models: [ModelInfo]
}

struct OAuthProviderStatus: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let authenticated: Bool
}
