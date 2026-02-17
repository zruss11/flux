import Foundation

enum ThinkingLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "XHigh"
        }
    }

    var next: ThinkingLevel {
        let levels = Self.allCases
        guard let currentIndex = levels.firstIndex(of: self) else { return .low }
        let nextIndex = (currentIndex + 1) % levels.count
        return levels[nextIndex]
    }
}

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
