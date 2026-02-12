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
    private var modifierPollTimer: DispatchSourceTimer?
    private var levelPollTimer: Timer?
    private var stopWatchdogWorkItem: DispatchWorkItem?
    private var recordingStartTime: Date?
    private var accessibilityReader: AccessibilityReader?
    private var activeAttemptId: UUID?

    /// Tracks whether the Cmd+Option modifier pair is currently held.
    private var isModifierHeld = false

    /// Work item used to debounce the key-down event before starting dictation.
    private var debounceWorkItem: DispatchWorkItem?

    private let minRecordingDuration: TimeInterval = 0.5
    private let maxContinuousRecordingDuration: TimeInterval = 45
    private let transcriptionStopTimeout: TimeInterval = 15

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
        startModifierPolling()

        Log.voice.info("Global dictation monitor started")
    }

    /// Stop listening for the dictation hotkey and tear down any active recording.
    func stop() {
        Log.voice.info("Global dictation monitor stopping")

        flagsMonitor?.stop()
        flagsMonitor = nil
        stopModifierPolling()

        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        isModifierHeld = false

        levelPollTimer?.invalidate()
        levelPollTimer = nil
        cancelStopWatchdog()

        if voiceInput?.isRecording == true {
            voiceInput?.stopRecording()
        }

        activeAttemptId = nil
        isDictating = false
        resetVisualState()

        voiceInput = nil
    }

    // MARK: - Flags Handling

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let bothPressed = flags.contains(.command) && flags.contains(.option)
        updateModifierState(isHeld: bothPressed)
    }

    private func updateModifierState(isHeld: Bool) {
        if isHeld && !isModifierHeld {
            Log.voice.debug("Global dictation hotkey pressed")
            isModifierHeld = true

            // Debounce: wait 80 ms before actually starting dictation to avoid
            // accidental triggers from fast modifier taps.
            let workItem = DispatchWorkItem { [weak self] in
                self?.beginDictation()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)

        } else if !isHeld && isModifierHeld {
            Log.voice.debug("Global dictation hotkey released")
            isModifierHeld = false

            // Cancel the debounce if the keys were released before it fired.
            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            if isDictating || voiceInput?.isRecording == true {
                endDictation()
            }
        }
    }

    // MARK: - Begin / End Dictation

    private func beginDictation() {
        guard !isDictating else { return }
        guard activeAttemptId == nil else {
            Log.voice.debug("Ignoring dictation start while previous attempt is still active")
            return
        }

        let attemptId = UUID()
        activeAttemptId = attemptId

        let input = VoiceInput()
        input.audioLevelMeter = audioLevelMeter
        voiceInput = input

        Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] begin")

        Task { @MainActor [weak self] in
            guard let self else { return }

            let permitted = await input.ensureMicrophonePermission()
            guard permitted else {
                self.handleRecordingFailure(
                    "Microphone permission not granted.",
                    attemptId: attemptId,
                    recordHistory: true
                )
                return
            }

            self.isDictating = true
            self.recordingStartTime = Date()
            AudioFeedbackService.shared.play(.dictationStart)

            IslandWindowManager.shared.suppressDeactivationCollapse = true

            // Poll audio levels at ~60 Hz to drive the in-notch waveform.
            self.levelPollTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 60.0,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleLevelPollTick()
                }
            }

            let started = await input.startRecording(
                mode: .batchOnDevice,
                onComplete: { [weak self] transcript in
                    self?.handleTranscript(transcript, attemptId: attemptId)
                },
                onFailure: { [weak self] reason in
                    self?.handleRecordingFailure(reason, attemptId: attemptId, recordHistory: true)
                }
            )

            guard self.isAttemptActive(attemptId) else {
                if started || input.isRecording {
                    Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] startup completed after attempt ended; stopping stale recorder")
                    input.stopRecording()
                }
                return
            }

            guard started else {
                self.handleRecordingFailure(
                    "Unable to start dictation recording.",
                    attemptId: attemptId,
                    recordHistory: true
                )
                return
            }

            Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] recording started")

            // If the user released Cmd+Option while recording was still starting up,
            // ensure we do not leave the microphone running.
            if !self.isDictating || !self.isModifierHeld {
                Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] released during startup")
                if input.isRecording {
                    input.stopRecording()
                }
                self.completeAttemptIfActive(attemptId)
                self.resetVisualState()
                self.isDictating = false
            }
        }
    }

    private func endDictation() {
        let attemptId = activeAttemptId
        isDictating = false

        levelPollTimer?.invalidate()
        levelPollTimer = nil

        guard let attemptId else {
            resetVisualState()
            return
        }

        guard voiceInput?.isRecording == true else {
            Log.voice.debug("[dictation \(attemptId.uuidString, privacy: .public)] stop requested without active recorder")
            completeAttemptIfActive(attemptId)
            resetVisualState()
            return
        }

        // Discard recordings shorter than 0.5 s — likely accidental triggers.
        let elapsed = Date().timeIntervalSince(recordingStartTime ?? Date())
        if elapsed < minRecordingDuration {
            Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] ignored short hold")
            completeAttemptIfActive(attemptId)
            voiceInput?.stopRecording()
            resetVisualState()
            return
        }

        isProcessing = true
        scheduleStopWatchdog(for: attemptId)

        Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] stopping recorder")
        // Stop recording; transcript/failure arrives via callbacks.
        AudioFeedbackService.shared.play(.dictationStop)
        voiceInput?.stopRecording()
    }

    // MARK: - Transcript Processing

    private func handleTranscript(_ rawTranscript: String, attemptId: UUID) {
        guard isAttemptActive(attemptId) else {
            Log.voice.debug("[dictation \(attemptId.uuidString, privacy: .public)] ignoring stale transcript callback")
            return
        }

        cancelStopWatchdog()

        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleRecordingFailure("No speech detected.", attemptId: attemptId, recordHistory: true)
            return
        }

        let duration = max(0, Date().timeIntervalSince(recordingStartTime ?? Date()))

        // Filler word cleaning (defaults to enabled).
        let cleanFillers = UserDefaults.standard.object(forKey: "dictationAutoCleanFillers") as? Bool ?? true
        let cleanedText = cleanFillers ? FillerWordCleaner.clean(rawTranscript) : rawTranscript

        // Enhancement mode.
        let enhancementModeRaw = UserDefaults.standard.string(forKey: "dictationEnhancementMode") ?? "none"

        Task { @MainActor [weak self] in
            guard let self, self.isAttemptActive(attemptId) else { return }

            // Apply custom dictionary corrections.
            let correctedText = DictionaryCorrector.apply(cleanedText, using: CustomDictionaryStore.shared.entries)

            var enhancedText: String?
            var enhancementMethod: DictationEntry.EnhancementMethod = .none

            if enhancementModeRaw == "foundationModels" {
                enhancedText = await self.enhanceWithFoundationModels(correctedText)
                if enhancedText != nil {
                    enhancementMethod = .foundationModels
                }
            }
            // "claude" enhancement is deferred to a future step.

            let finalText = enhancedText ?? correctedText

            // Determine the target application before inserting.
            let targetApp = self.accessibilityReader?.focusedFieldAppName()

            // Insert text into the focused field, or fall back to the pasteboard.
            let inserted = self.accessibilityReader?.insertTextAtFocusedField(finalText) ?? false
            if !inserted {
                ClipboardMonitor.shared.beginSelfCopy()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
                ClipboardMonitor.shared.endSelfCopy()
                Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] inserted via clipboard fallback")
            } else {
                Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] inserted into focused field")
            }

            AudioFeedbackService.shared.play(.dictationSuccess)

            // Persist the entry in history.
            let entry = DictationEntry(
                rawTranscript: rawTranscript,
                cleanedText: cleanedText,
                enhancedText: enhancedText,
                finalText: finalText,
                duration: duration,
                timestamp: Date(),
                targetApp: targetApp,
                enhancementMethod: enhancementMethod,
                status: .success,
                failureReason: nil
            )
            self.historyStore.add(entry)
            Log.voice.info("[dictation \(attemptId.uuidString, privacy: .public)] completed successfully")

            self.completeAttemptIfActive(attemptId)
            self.resetVisualState()
        }
    }

    private func handleRecordingFailure(_ reason: String, attemptId: UUID, recordHistory: Bool) {
        guard isAttemptActive(attemptId) else { return }

        cancelStopWatchdog()

        if voiceInput?.isRecording == true {
            voiceInput?.stopRecording()
        }

        let duration = max(0, Date().timeIntervalSince(recordingStartTime ?? Date()))
        let targetApp = accessibilityReader?.focusedFieldAppName()

        if recordHistory {
            let entry = DictationEntry(
                rawTranscript: "",
                cleanedText: "",
                enhancedText: nil,
                finalText: "",
                duration: duration,
                timestamp: Date(),
                targetApp: targetApp,
                enhancementMethod: .none,
                status: .failed,
                failureReason: reason
            )
            historyStore.add(entry)
        }

        Log.voice.error("[dictation \(attemptId.uuidString, privacy: .public)] failed: \(reason, privacy: .public)")
        IslandWindowManager.shared.showDictationNotification("Dictation failed: \(reason)")

        completeAttemptIfActive(attemptId)
        isDictating = false
        resetVisualState()
    }

    // MARK: - Foundation Models Enhancement

    private func enhanceWithFoundationModels(_ text: String) async -> String? {
        guard FoundationModelsClient.shared.isAvailable else { return nil }
        return try? await FoundationModelsClient.shared.completeText(
            system: "Clean up dictated text for grammar and punctuation. Preserve meaning and tone. Return only the cleaned text.",
            user: text
        )
    }

    private func startModifierPolling() {
        stopModifierPolling()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            let held = Self.isHotkeyHeldGlobally()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateModifierState(isHeld: held)
            }
        }
        timer.resume()
        modifierPollTimer = timer
    }

    private func stopModifierPolling() {
        modifierPollTimer?.cancel()
        modifierPollTimer = nil
    }

    private func handleLevelPollTick() {
        let now = Date()

        // Failsafe: if modifier-up is missed but recording is still active,
        // force end dictation based on global key state.
        if !Self.isHotkeyHeldGlobally(),
           (isDictating || voiceInput?.isRecording == true) {
            endDictation()
            return
        }

        if (isDictating || voiceInput?.isRecording == true),
           let start = recordingStartTime,
           now.timeIntervalSince(start) >= maxContinuousRecordingDuration {
            if let attemptId = activeAttemptId {
                Log.voice.error("[dictation \(attemptId.uuidString, privacy: .public)] exceeded max recording duration")
            }
            endDictation()
            return
        }

        let levels = audioLevelMeter.currentLevels()
        barLevels = levels.bars
    }

    private func scheduleStopWatchdog(for attemptId: UUID) {
        cancelStopWatchdog()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleRecordingFailure(
                    "Timed out waiting for transcription result.",
                    attemptId: attemptId,
                    recordHistory: true
                )
            }
        }
        stopWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptionStopTimeout, execute: workItem)
    }

    private func cancelStopWatchdog() {
        stopWatchdogWorkItem?.cancel()
        stopWatchdogWorkItem = nil
    }

    private func isAttemptActive(_ attemptId: UUID) -> Bool {
        activeAttemptId == attemptId
    }

    private func completeAttemptIfActive(_ attemptId: UUID) {
        guard activeAttemptId == attemptId else { return }
        activeAttemptId = nil
        cancelStopWatchdog()
    }

    private func resetVisualState() {
        levelPollTimer?.invalidate()
        levelPollTimer = nil
        barLevels = Array(repeating: 0, count: 16)
        isProcessing = false
        IslandWindowManager.shared.suppressDeactivationCollapse = false
        audioLevelMeter.reset()
        recordingStartTime = nil
    }

    private nonisolated static func isHotkeyHeldGlobally() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskCommand) && flags.contains(.maskAlternate)
    }
}
