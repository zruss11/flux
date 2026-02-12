import AppKit
import Foundation

@Observable
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    let store = ClipboardHistoryStore()
    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0
    private var selfCopyDepth: Int = 0

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard pollTimer == nil else { return }
        Log.clipboard.info("Clipboard monitor started")
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        Log.clipboard.info("Clipboard monitor stopped")
    }

    func beginSelfCopy() {
        selfCopyDepth += 1
    }

    func endSelfCopy() {
        selfCopyDepth = max(0, selfCopyDepth - 1)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard selfCopyDepth == 0 else { return }

        guard let content = NSPasteboard.general.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let contentType = classifyContent(content)

        let entry = ClipboardEntry(
            content: content,
            sourceApp: sourceApp,
            contentType: contentType
        )
        store.add(entry)
        Log.clipboard.debug("Captured clipboard entry from \(sourceApp ?? "unknown", privacy: .public)")
    }

    private func classifyContent(_ text: String) -> ClipboardEntry.ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .url
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return .filePath
        }
        return .plainText
    }
}
