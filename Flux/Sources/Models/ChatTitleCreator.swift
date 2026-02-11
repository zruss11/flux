import Foundation

enum ChatTitleCreator: String, CaseIterable, Identifiable {
    case firstUserMessage
    case foundationModels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstUserMessage: return "First user message"
        case .foundationModels: return "Apple Foundation Models"
        }
    }
}

