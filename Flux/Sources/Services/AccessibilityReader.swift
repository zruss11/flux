@preconcurrency import ApplicationServices
import AppKit

@Observable
@MainActor
final class AccessibilityReader {
    private let maxChildren = 50
    private let maxDepth = 10
    private let defaultVisibleWindowApps = 10
    private let defaultVisibleWindowsPerApp = 4
    private let defaultVisibleElementsPerWindow = 60
    private let defaultVisibleWindowTextLength = 280

    var isPermissionGranted = false

    func checkPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isPermissionGranted = trusted
        return trusted
    }

    func readFrontmostWindow() async -> AXNode? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else { return nil }

        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return extractTree(from: window as! AXUIElement, depth: 0)
    }

    func readSelectedText() async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else { return nil }

        return text
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func insertTextAtFocusedField(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return false }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return false }

        let axElement = element as! AXUIElement

        // Attempt 1: Set via kAXValueAttribute
        let valueResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        if valueResult == .success {
            return true
        }

        // Attempt 2: Set via kAXSelectedTextAttribute
        let selectedResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if selectedResult == .success {
            return true
        }

        // Attempt 3: Pasteboard fallback (simulate Cmd+V)
        let savedPasteboard = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let original = savedPasteboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(original, forType: .string)
            }
        }

        return true
    }

    func focusedFieldAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func readVisibleWindowsContext(
        maxApps: Int?,
        maxWindowsPerApp: Int?,
        maxElementsPerWindow: Int?,
        maxTextLength: Int?,
        includeMinimized: Bool?
    ) async -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let boundedApps = clamp(maxApps ?? defaultVisibleWindowApps, min: 1, max: 25)
        let boundedWindows = clamp(maxWindowsPerApp ?? defaultVisibleWindowsPerApp, min: 1, max: 12)
        let boundedElements = clamp(maxElementsPerWindow ?? defaultVisibleElementsPerWindow, min: 1, max: 250)
        let boundedTextLength = clamp(maxTextLength ?? defaultVisibleWindowTextLength, min: 50, max: 1_000)
        let includeMinimizedWindows = includeMinimized ?? false

        let script = visibleWindowsAppleScript(
            maxApps: boundedApps,
            maxWindowsPerApp: boundedWindows,
            maxElementsPerWindow: boundedElements,
            maxTextLength: boundedTextLength,
            includeMinimized: includeMinimizedWindows
        )

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            return "AppleScript error: \(error)"
        }

        return result?.stringValue ?? "{\"source\":\"read_visible_windows\",\"apps\":[]}"
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

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func visibleWindowsAppleScript(
        maxApps: Int,
        maxWindowsPerApp: Int,
        maxElementsPerWindow: Int,
        maxTextLength: Int,
        includeMinimized: Bool
    ) -> String {
        #"""
        use scripting additions

        on replaceText(findText, replacementText, sourceText)
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to findText
            set textItems to every text item of sourceText
            set AppleScript's text item delimiters to replacementText
            set joinedText to textItems as text
            set AppleScript's text item delimiters to previousDelimiters
            return joinedText
        end replaceText

        on joinJson(listItems)
            if (count of listItems) is 0 then return ""
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to ","
            set joinedText to listItems as text
            set AppleScript's text item delimiters to previousDelimiters
            return joinedText
        end joinJson

        on truncateText(rawValue, maxLength)
            if rawValue is missing value then return ""
            set rawText to ""
            try
                set rawText to rawValue as text
            on error
                return ""
            end try

            if (count of rawText) > maxLength then
                return text 1 thru maxLength of rawText
            end if
            return rawText
        end truncateText

        on jsonEscape(rawValue, maxLength)
            set textValue to my truncateText(rawValue, maxLength)
            set textValue to my replaceText("\\", "\\\\", textValue)
            set textValue to my replaceText("\"", "\\\"", textValue)
            set textValue to my replaceText(return, "\\n", textValue)
            set textValue to my replaceText(linefeed, "\\n", textValue)
            set textValue to my replaceText(tab, "\\t", textValue)
            return textValue
        end jsonEscape

        on quoted(rawValue, maxLength)
            return "\"" & my jsonEscape(rawValue, maxLength) & "\""
        end quoted

        on attrValue(uiRef, attrName, maxLength)
            try
                set attrRawValue to value of attribute attrName of uiRef
                return my truncateText(attrRawValue, maxLength)
            on error
                return ""
            end try
        end attrValue

        set maxApps to \#(maxApps)
        set maxWindowsPerApp to \#(maxWindowsPerApp)
        set maxElementsPerWindow to \#(maxElementsPerWindow)
        set maxTextLength to \#(maxTextLength)
        set includeMinimizedWindows to \#(includeMinimized ? "true" : "false")

        set appsJson to {}
        set truncatedApps to false

        tell application "System Events"
            set procList to every application process whose background only is false
            set procCount to count of procList
            set appLimit to procCount
            if appLimit > maxApps then
                set appLimit to maxApps
                set truncatedApps to true
            end if

            repeat with appIndex from 1 to appLimit
                set procRef to item appIndex of procList
                set appName to ""
                set pidValue to 0

                try
                    set appName to name of procRef
                end try

                try
                    set pidValue to unix id of procRef
                end try

                set windowRefs to {}
                try
                    set windowRefs to windows of procRef
                end try

                set totalWindowCount to count of windowRefs
                set truncatedWindows to false
                if totalWindowCount > maxWindowsPerApp then
                    set truncatedWindows to true
                end if

                set windowJson to {}
                repeat with windowRef in windowRefs
                    if (count of windowJson) is greater than or equal to maxWindowsPerApp then exit repeat
                    set isMinimized to false
                    try
                        set isMinimized to value of attribute "AXMinimized" of windowRef
                    end try

                    if includeMinimizedWindows or isMinimized is false then
                        set isVisible to true
                        try
                            set isVisible to value of attribute "AXVisible" of windowRef
                        end try

                        if isVisible then
                            set windowTitle to my attrValue(windowRef, "AXTitle", maxTextLength)
                            set windowRole to my attrValue(windowRef, "AXRole", maxTextLength)
                            set windowSubrole to my attrValue(windowRef, "AXSubrole", maxTextLength)

                            set elementRefs to {}
                            try
                                set elementRefs to entire contents of windowRef
                            on error
                                try
                                    set elementRefs to UI elements of windowRef
                                end try
                            end try

                            set elementCount to count of elementRefs
                            set elementLimit to elementCount
                            set truncatedElements to false
                            if elementLimit > maxElementsPerWindow then
                                set elementLimit to maxElementsPerWindow
                                set truncatedElements to true
                            end if

                            set elementJson to {}
                            repeat with elementIndex from 1 to elementLimit
                                set elementRef to item elementIndex of elementRefs
                                set elementRole to my attrValue(elementRef, "AXRole", maxTextLength)
                                set elementTitle to my attrValue(elementRef, "AXTitle", maxTextLength)
                                set elementValue to my attrValue(elementRef, "AXValue", maxTextLength)
                                set elementDescription to my attrValue(elementRef, "AXDescription", maxTextLength)

                                if elementRole is not "" or elementTitle is not "" or elementValue is not "" or elementDescription is not "" then
                                    set entry to "{"
                                    set entry to entry & "\"role\":" & my quoted(elementRole, maxTextLength)
                                    set entry to entry & ",\"title\":" & my quoted(elementTitle, maxTextLength)
                                    set entry to entry & ",\"value\":" & my quoted(elementValue, maxTextLength)
                                    set entry to entry & ",\"description\":" & my quoted(elementDescription, maxTextLength)
                                    set entry to entry & "}"
                                    copy entry to end of elementJson
                                end if
                            end repeat

                            set elementsArray to "[]"
                            if (count of elementJson) > 0 then
                                set elementsArray to "[" & my joinJson(elementJson) & "]"
                            end if

                            set windowEntry to "{"
                            set windowEntry to windowEntry & "\"title\":" & my quoted(windowTitle, maxTextLength)
                            set windowEntry to windowEntry & ",\"role\":" & my quoted(windowRole, maxTextLength)
                            set windowEntry to windowEntry & ",\"subrole\":" & my quoted(windowSubrole, maxTextLength)
                            set windowEntry to windowEntry & ",\"minimized\":" & (isMinimized as text)
                            set windowEntry to windowEntry & ",\"visible\":" & (isVisible as text)
                            set windowEntry to windowEntry & ",\"elementCount\":" & elementCount
                            set windowEntry to windowEntry & ",\"truncatedElements\":" & (truncatedElements as text)
                            set windowEntry to windowEntry & ",\"elements\":" & elementsArray
                            set windowEntry to windowEntry & "}"
                            copy windowEntry to end of windowJson
                        end if
                    end if
                end repeat

                if (count of windowJson) > 0 then
                    set windowsArray to "[" & my joinJson(windowJson) & "]"
                    set appEntry to "{"
                    set appEntry to appEntry & "\"app\":" & my quoted(appName, maxTextLength)
                    set appEntry to appEntry & ",\"pid\":" & pidValue
                    set appEntry to appEntry & ",\"totalWindowCount\":" & totalWindowCount
                    set appEntry to appEntry & ",\"windowCount\":" & (count of windowJson)
                    set appEntry to appEntry & ",\"truncatedWindows\":" & (truncatedWindows as text)
                    set appEntry to appEntry & ",\"windows\":" & windowsArray
                    set appEntry to appEntry & "}"
                    copy appEntry to end of appsJson
                end if
            end repeat
        end tell

        set appsArray to "[]"
        if (count of appsJson) > 0 then
            set appsArray to "[" & my joinJson(appsJson) & "]"
        end if

        set resultJson to "{"
        set resultJson to resultJson & "\"source\":\"read_visible_windows\""
        set resultJson to resultJson & ",\"maxApps\":" & maxApps
        set resultJson to resultJson & ",\"maxWindowsPerApp\":" & maxWindowsPerApp
        set resultJson to resultJson & ",\"maxElementsPerWindow\":" & maxElementsPerWindow
        set resultJson to resultJson & ",\"maxTextLength\":" & maxTextLength
        set resultJson to resultJson & ",\"includeMinimized\":" & (includeMinimizedWindows as text)
        set resultJson to resultJson & ",\"truncatedApps\":" & (truncatedApps as text)
        set resultJson to resultJson & ",\"apps\":" & appsArray
        set resultJson to resultJson & "}"
        return resultJson
        """#
    }
}
