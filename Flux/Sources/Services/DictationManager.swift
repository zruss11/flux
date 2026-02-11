import AppKit
import AVFoundation
import Foundation

// MARK: - DictationManager

/// Orchestrates system-wide voice dictation triggered by Cmd+Option hold.
///
/// Listens for modifier key events, manages recording via a dedicated `VoiceInput`
/// instance, displays a waveform panel alongside the notch, cleans/enhances the
/// transcribed text, and inserts it into the focused text field (or copies to pasteboard
/// as a fallback).
@Observable
@MainActor
final class DictationManager {

    static let shared = DictationManager()

    // MARK: - Public State

    private(set) var isDictating = false

    let historyStore = DictationHistoryStore()

    // MARK: - Private Properties

    private var voiceInput: VoiceInput?
    private let audioLevelMeter = AudioLevelMeter()

    /// Bar levels exposed for in-notch waveform rendering.
    private(set) var barLevels: [Float] = Array(repeating: 0, count: 16)
    private(set) var isProcessing = false

    private var flagsMonitor: EventMonitor?
    private var levelPollTimer: Timer?
    private var recordingStartTime: Date?
    private var accessibilityReader: AccessibilityReader?

    /// Tracks whether the Cmd+Option modifier pair is currently held.
    private var isModifierHeld = false

    /// Work item used to debounce the key-down event before starting dictation.
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - Init

    private init() {}

    // MARK: - Public Methods

    /// Begin listening for the Cmd+Option dictation hotkey.
    ///
    /// - Parameter accessibilityReader: The reader used to insert text into the focused
    ///   field and to determine the target application name.
    func start(accessibilityReader: AccessibilityReader) {
        self.accessibilityReader = accessibilityReader

        flagsMonitor = EventMonitor(mask: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        flagsMonitor?.start()
    }

    /// Stop listening for the dictation hotkey and tear down any active recording.
    func stop() {
        flagsMonitor?.stop()
        flagsMonitor = nil

        levelPollTimer?.invalidate()
        levelPollTimer = nil

        if isDictating {
            voiceInput?.stopRecording()
            isDictating = false
            barLevels = Array(repeating: 0, count: 16)
            isProcessing = false
            IslandWindowManager.shared.suppressDeactivationCollapse = false
        }

        voiceInput = nil
    }

    // MARK: - Flags Handling

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let bothPressed = flags.contains(.command) && flags.contains(.option)

        if bothPressed && !isModifierHeld {
            isModifierHeld = true

            // Debounce: wait 80 ms before actually starting dictation to avoid
            // accidental triggers from fast modifier taps.
            let workItem = DispatchWorkItem { [weak self] in
                self?.beginDictation()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)

        } else if !bothPressed && isModifierHeld {
            isModifierHeld = false

            // Cancel the debounce if the keys were released before it fired.
            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            if isDictating {
                endDictation()
            }
        }
    }

    // MARK: - Begin / End Dictation

    private func beginDictation() {
        guard !isDictating else { return }

        let input = VoiceInput()
        input.audioLevelMeter = audioLevelMeter
        self.voiceInput = input

        Task { @MainActor [weak self] in
            guard let self else { return }

            let permitted = await input.ensureMicrophonePermission()
            guard permitted else { return }

            self.isDictating = true
            self.recordingStartTime = Date()

            IslandWindowManager.shared.suppressDeactivationCollapse = true

            // Poll audio levels at ~60 Hz to drive the in-notch waveform.
            self.levelPollTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 60.0,
                repeats: true
            ) { [weak self] _ in
                guard let self else { return }
                let levels = self.audioLevelMeter.currentLevels()
                Task { @MainActor in
                    self.barLevels = levels.bars
                }
            }

            await input.startRecording { [weak self] transcript in
                self?.handleTranscript(transcript)
            }
        }
    }

    private func endDictation() {
        guard isDictating else { return }
        isDictating = false

        levelPollTimer?.invalidate()
        levelPollTimer = nil

        isProcessing = true

        // Discard recordings shorter than 0.5 s — likely accidental triggers.
        let elapsed = Date().timeIntervalSince(recordingStartTime ?? Date())
        if elapsed < 0.5 {
            voiceInput?.stopRecording()
            barLevels = Array(repeating: 0, count: 16)
            isProcessing = false
            IslandWindowManager.shared.suppressDeactivationCollapse = false
            audioLevelMeter.reset()
            recordingStartTime = nil
            return
        }

        // Stop recording; the transcript will arrive via the `handleTranscript` callback.
        voiceInput?.stopRecording()
    }

    // MARK: - Transcript Processing

    private func handleTranscript(_ rawTranscript: String) {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            barLevels = Array(repeating: 0, count: 16)
            isProcessing = false
            IslandWindowManager.shared.suppressDeactivationCollapse = false
            audioLevelMeter.reset()
            recordingStartTime = nil
            return
        }

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        // Filler word cleaning (defaults to enabled).
        let cleanFillers = UserDefaults.standard.object(forKey: "dictationAutoCleanFillers") as? Bool ?? true
        let cleanedText = cleanFillers ? FillerWordCleaner.clean(rawTranscript) : rawTranscript

        // Enhancement mode.
        let enhancementModeRaw = UserDefaults.standard.string(forKey: "dictationEnhancementMode") ?? "none"

        Task { @MainActor [weak self] in
            guard let self else { return }

            var enhancedText: String?
            var enhancementMethod: DictationEntry.EnhancementMethod = .none

            if enhancementModeRaw == "foundationModels" {
                enhancedText = await self.enhanceWithFoundationModels(cleanedText)
                if enhancedText != nil {
                    enhancementMethod = .foundationModels
                }
            }
            // "claude" enhancement is deferred to a future step.

            let finalText = enhancedText ?? cleanedText

            // Determine the target application before inserting.
            let targetApp = self.accessibilityReader?.focusedFieldAppName()

            // Insert text into the focused field, or fall back to the pasteboard.
            let inserted = self.accessibilityReader?.insertTextAtFocusedField(finalText) ?? false

            if !inserted {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
            }

            // Persist the entry in history.
            let entry = DictationEntry(
                rawTranscript: rawTranscript,
                cleanedText: cleanedText,
                enhancedText: enhancedText,
                finalText: finalText,
                duration: duration,
                timestamp: Date(),
                targetApp: targetApp,
                enhancementMethod: enhancementMethod
            )
            self.historyStore.add(entry)

            // Tear down UI.
            self.barLevels = Array(repeating: 0, count: 16)
            self.isProcessing = false
            IslandWindowManager.shared.suppressDeactivationCollapse = false
            self.audioLevelMeter.reset()
            self.recordingStartTime = nil
        }
    }

    // MARK: - Foundation Models Enhancement

    private func enhanceWithFoundationModels(_ text: String) async -> String? {
        guard FoundationModelsClient.shared.isAvailable else { return nil }
        return try? await FoundationModelsClient.shared.completeText(
            system: "Clean up dictated text for grammar and punctuation. Preserve meaning and tone. Return only the cleaned text.",
            user: text
        )
    }
}
