import Foundation
import AppKit

/// Orchestrates "Magic Replace" — transforming selected text via an AI voice command.
///
/// Tries Apple Foundation Models first (on-device, fast) then falls back to the
/// Anthropic Messages API. Manages undo state and a brief "Undo" pill affordance.
@Observable
@MainActor
final class MagicReplaceManager {

    static let shared = MagicReplaceManager()

    // MARK: - Public State

    private(set) var isProcessing = false
    private(set) var showUndoPill = false

    // MARK: - Private State

    private var undoTargetPID: pid_t?
    private var undoDismissWorkItem: DispatchWorkItem?

    struct ReplaceResult {
        let inserted: Bool
        let transformedText: String?
    }

    private init() {}

    // MARK: - Perform Replace

    /// Transform the selected text according to a voice command and replace it in-place.
    ///
    /// - Returns: Result describing whether insertion succeeded and the transformed text, if any.
    @discardableResult
    func performReplace(
        selectedText: String,
        command: String,
        accessibilityReader: AccessibilityReader
    ) async -> ReplaceResult {
        isProcessing = true
        defer { isProcessing = false }

        // Pin the focused element before async work so replacement targets
        // the correct field even if the user changes focus while waiting.
        let captured = accessibilityReader.captureFocusedElement()

        let transformed = await transformText(selectedText: selectedText, command: command)

        guard let result = transformed, !result.isEmpty else {
            return ReplaceResult(inserted: false, transformedText: nil)
        }

        // Store target app PID for undo.
        undoTargetPID = captured?.appPID

        let inserted: Bool
        if let captured {
            inserted = accessibilityReader.replaceSelectedText(result, in: captured)
        } else {
            inserted = accessibilityReader.replaceSelectedText(result)
        }

        if inserted {
            showUndoPillBriefly()
        }

        return ReplaceResult(inserted: inserted, transformedText: result)
    }

    // MARK: - Undo

    func undoLastReplace() {
        // Re-activate the target app before sending Cmd+Z so the undo
        // reaches the correct application regardless of current focus.
        if let pid = undoTargetPID,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        // Send Cmd+Z to undo the replacement via the system undo stack.
        let source = CGEventSource(stateID: .hidSystemState)
        let zKeyCode: CGKeyCode = 6
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: zKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: zKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        undoTargetPID = nil
        showUndoPill = false
        undoDismissWorkItem?.cancel()
    }

    // MARK: - Text Transformation

    private func transformText(selectedText: String, command: String) async -> String? {
        // Try on-device Foundation Models first.
        if FoundationModelsClient.shared.isAvailable {
            if let result = try? await FoundationModelsClient.shared.completeText(
                system: Self.systemPrompt,
                user: Self.buildUserPrompt(selectedText: selectedText, command: command)
            ) {
                return result
            }
        }

        // Fall back to Anthropic API.
        return await callAnthropicAPI(selectedText: selectedText, command: command)
    }

    // MARK: - Anthropic API

    private func callAnthropicAPI(selectedText: String, command: String) async -> String? {
        guard let apiKey = UserDefaults.standard.string(forKey: "anthropicApiKey"),
              !apiKey.isEmpty else { return nil }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": Self.buildUserPrompt(selectedText: selectedText, command: command)]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = (json["content"] as? [[String: Any]])?.first,
                  let text = content["text"] as? String else { return nil }

            return text
        } catch {
            return nil
        }
    }

    // MARK: - Undo Pill

    private func showUndoPillBriefly() {
        undoDismissWorkItem?.cancel()
        showUndoPill = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.showUndoPill = false
        }
        undoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    // MARK: - Prompts

    private static let systemPrompt = """
        You are a precise text editor. The user has selected text and given a voice command \
        describing how to transform it. Return ONLY the transformed text with no explanation, \
        no quotes, no markdown formatting. Preserve the original formatting style (capitalization, \
        punctuation patterns) unless the command specifically asks to change it.
        """

    private static func buildUserPrompt(selectedText: String, command: String) -> String {
        """
        Selected text:
        \(selectedText)

        Command: \(command)
        """
    }
}
