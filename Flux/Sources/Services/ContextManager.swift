import Foundation

@MainActor
final class ContextManager {
    private let accessibilityReader = AccessibilityReader()
    private let screenCapture = ScreenCapture()

    func gatherContext(includeScreenshot: Bool = false) async -> ScreenContext {
        var context = ScreenContext()

        context.frontmostApp = accessibilityReader.frontmostAppName()
        context.axTree = await accessibilityReader.readFrontmostWindow()
        context.selectedText = await accessibilityReader.readSelectedText()

        if includeScreenshot {
            context.screenshot = await screenCapture.captureFrontmostWindow()
        }

        return context
    }

    func checkPermissions() -> (accessibility: Bool, screenRecording: Bool) {
        let ax = accessibilityReader.checkPermission()
        let sc = screenCapture.checkPermission()
        return (ax, sc)
    }
}
