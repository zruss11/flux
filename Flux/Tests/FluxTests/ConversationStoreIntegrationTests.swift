import Foundation
import XCTest

@testable import Flux

@MainActor
final class ConversationStoreIntegrationTests: XCTestCase {
    func testConversationStorePersistsConversation() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("flux-history-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Clean up any existing state first
        try? fm.removeItem(at: tempDir)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        ConversationStore.overrideHistoryDirectory = tempDir
        defer {
            ConversationStore.overrideHistoryDirectory = nil
            try? fm.removeItem(at: tempDir)
        }

        UserDefaults.standard.set(ChatTitleCreator.firstUserMessage.rawValue, forKey: "chatTitleCreator")
        defer {
            UserDefaults.standard.removeObject(forKey: "chatTitleCreator")
        }

        let store = ConversationStore()
        let conversation = store.createConversation()
        store.addMessage(to: conversation.id, role: .user, content: "Hello Flux")
        store.addMessage(to: conversation.id, role: .assistant, content: "Hi there")

        // Force synchronous save for test stability
        // Get the updated conversation from the store (it has the messages now)
        if let updatedConversation = store.conversations.first(where: { $0.id == conversation.id }) {
            store.saveConversationSync(updatedConversation)
        }
        store.saveIndexSync()

        let storeReloaded = ConversationStore()
        storeReloaded.openConversation(id: conversation.id)

        XCTAssertEqual(storeReloaded.summaries.count, 1, "Expected exactly 1 conversation but found \(storeReloaded.summaries.count)")
        XCTAssertEqual(storeReloaded.summaries.first?.messageCount, 2)
        XCTAssertEqual(storeReloaded.activeConversation?.messages.count, 2)
        XCTAssertEqual(storeReloaded.activeConversation?.messages.first?.content, "Hello Flux")
    }
}
