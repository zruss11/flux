import Foundation
import XCTest

@testable import Flux

@MainActor
final class ConversationStoreIntegrationTests: XCTestCase {
    func testConversationStorePersistsConversation() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("flux-history-\(UUID().uuidString)", isDirectory: true)
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

        // Wait for async saves to complete (file I/O is now async)
        Thread.sleep(forTimeInterval: 0.5)

        let storeReloaded = ConversationStore()
        storeReloaded.openConversation(id: conversation.id)

        XCTAssertEqual(storeReloaded.summaries.count, 1)
        XCTAssertEqual(storeReloaded.summaries.first?.messageCount, 2)
        XCTAssertEqual(storeReloaded.activeConversation?.messages.count, 2)
        XCTAssertEqual(storeReloaded.activeConversation?.messages.first?.content, "Hello Flux")
    }
}
