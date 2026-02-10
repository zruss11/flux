@preconcurrency import ApplicationServices
import AppKit

@Observable
@MainActor
final class AccessibilityReader {
    private let maxChildren = 50
    private let maxDepth = 10

    var isPermissionGranted = false

    func checkPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isPermissionGranted = trusted
        return trusted
    }

    func readFrontmostWindow() async -> AXNode? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else { return nil }

        return extractTree(from: window as! AXUIElement, depth: 0)
    }

    func readSelectedText() async -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else { return nil }

        return text
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func extractTree(from element: AXUIElement, depth: Int) -> AXNode? {
        guard depth < maxDepth else { return nil }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

        var description: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)

        var childElements: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childElements)

        var children: [AXNode]? = nil
        if let childArray = childElements as? [AXUIElement] {
            let limited = Array(childArray.prefix(maxChildren))
            children = limited.compactMap { extractTree(from: $0, depth: depth + 1) }
            if children?.isEmpty == true { children = nil }
        }

        return AXNode(
            role: role as? String ?? "Unknown",
            title: title as? String,
            value: value as? String,
            nodeDescription: description as? String,
            children: children
        )
    }
}
