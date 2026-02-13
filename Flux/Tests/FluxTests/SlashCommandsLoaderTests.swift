import Foundation
import XCTest

@testable import Flux

final class SlashCommandsLoaderTests: XCTestCase {
    func testLoadCommandsPreservesRelativePathForDuplicateBasenames() throws {
        let fm = FileManager.default
        let tempWorkspace = fm.temporaryDirectory.appendingPathComponent(
            "flux-slash-commands-\(UUID().uuidString)",
            isDirectory: true
        )
        let commandsRoot = tempWorkspace
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("commands", isDirectory: true)

        let sharedPrefix = "test-\(UUID().uuidString.lowercased())"
        let gitReview = commandsRoot.appendingPathComponent("\(sharedPrefix)/git/review.md")
        let docsReview = commandsRoot.appendingPathComponent("\(sharedPrefix)/docs/review.md")

        try fm.createDirectory(
            at: gitReview.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: docsReview.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# review".write(to: gitReview, atomically: true, encoding: .utf8)
        try "# review".write(to: docsReview, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: tempWorkspace) }

        let commands = SlashCommandsLoader.loadCommands(workspacePath: tempWorkspace.path)
        let projectNames = Set(commands.filter { $0.source == .project }.map(\.name))

        XCTAssertTrue(projectNames.contains("\(sharedPrefix)/git/review"))
        XCTAssertTrue(projectNames.contains("\(sharedPrefix)/docs/review"))
    }
}
