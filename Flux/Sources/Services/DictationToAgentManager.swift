import AppKit
import AVFoundation
import Foundation

/// Orchestrates voice dictation triggered by Control+Option hold that sends
/// the transcript directly to the Flux chat as a new agent message.
///
/// Unlike `DictationManager` (Cmd+Option) which inserts text into the focused
/// field, this manager opens the island chat and fires off a new agent run.
@Observable
@MainActor
final class DictationToAgentManager {

    static let shared = DictationToAgentManager()

    // MARK: - Public State

    private(set) var isDictating = false
    private(set) var isProcessing = false

    /// Live transcript text updated in real-time during dictation.
    var liveTranscript: String {
        voiceInput?.transcript ?? ""
    }

    /// Bar levels exposed for waveform rendering.
    private(set) var barLevels: [Float] = Array(repeating: 0, count: 16)

    // MARK: - Private Properties

    private var voiceInput: VoiceInput?
    private let audioLevelMeter = AudioLevelMeter()

    private var flagsMonitor: EventMonitor?
    private var modifierPollTimer: DispatchSourceTimer?
    private var levelPollTimer: Timer?
    private var recordingStartTime: Date?
    private var activeAttemptId: UUID?

    private var isModifierHeld = false
    private var debounceWorkItem: DispatchWorkItem?
    private var stopWatchdogWorkItem: DispatchWorkItem?

    private let minRecordingDuration: TimeInterval = 0.5
    private let maxContinuousRecordingDuration: TimeInterval = 120
    private let transcriptionStopTimeout: TimeInterval = 15

    /// Dependencies injected via `start(...)`.
    private var conversationStore: ConversationStore?
    private var agentBridge: AgentBridge?
    private var screenCapture: ScreenCapture?

    // MARK: - Init

    private init() {}

    // MARK: - Public Methods

    /// Begin listening for the Control+Option dictation-to-agent hotkey.
    func start(
        conversationStore: ConversationStore,
        agentBridge: AgentBridge,
        screenCapture: ScreenCapture
    ) {
        self.conversationStore = conversationStore
        self.agentBridge = agentBridge
        self.screenCapture = screenCapture

        flagsMonitor = EventMonitor(mask: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        flagsMonitor?.start()
        startModifierPolling()

        Log.voice.info("DictationToAgent monitor started (Control+Option)")
    }

    /// Stop listening and tear down any active recording.
    func stop() {
        Log.voice.info("DictationToAgent monitor stopping")

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
        let bothPressed = flags.contains(.control) && flags.contains(.option) && !flags.contains(.command)
        updateModifierState(isHeld: bothPressed)
    }

    private func updateModifierState(isHeld: Bool) {
        if isHeld && !isModifierHeld {
            Log.voice.debug("DictationToAgent hotkey pressed (Control+Option)")
            isModifierHeld = true

            let workItem = DispatchWorkItem { [weak self] in
                self?.beginDictation()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)

        } else if !isHeld && isModifierHeld {
            Log.voice.debug("DictationToAgent hotkey released")
            isModifierHeld = false

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
        guard activeAttemptId == nil else { return }

        let attemptId = UUID()
        activeAttemptId = attemptId

        let input = VoiceInput()
        input.audioLevelMeter = audioLevelMeter
        voiceInput = input

        Log.voice.info("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] begin")

        Task { @MainActor [weak self] in
            guard let self else { return }

            let permitted = await input.ensureMicrophonePermission()
            guard permitted else {
                self.handleFailure("Microphone permission not granted.", attemptId: attemptId)
                return
            }

            self.isDictating = true
            self.recordingStartTime = Date()
            AudioFeedbackService.shared.play(.dictationStart)

            IslandWindowManager.shared.suppressDeactivationCollapse = true

            self.levelPollTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 60.0,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleLevelPollTick()
                }
            }

            let selectedEngine = self.selectedEngine()
            var startFailureReason: String?
            let started = await input.startRecording(
                mode: selectedEngine,
                onComplete: { [weak self] transcript in
                    self?.handleTranscript(transcript, attemptId: attemptId)
                },
                onFailure: { [weak self] reason in
                    startFailureReason = reason
                    self?.handleFailure(reason, attemptId: attemptId)
                }
            )

            guard self.isAttemptActive(attemptId) else {
                if started || input.isRecording {
                    input.stopRecording()
                }
                return
            }

            guard started else {
                if startFailureReason == nil {
                    self.handleFailure("Unable to start dictation recording.", attemptId: attemptId)
                }
                return
            }

            Log.voice.info("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] recording started")

            if !self.isDictating || !self.isModifierHeld {
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
            completeAttemptIfActive(attemptId)
            resetVisualState()
            return
        }

        let elapsed = Date().timeIntervalSince(recordingStartTime ?? Date())
        if elapsed < minRecordingDuration {
            Log.voice.info("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] ignored short hold")
            completeAttemptIfActive(attemptId)
            voiceInput?.stopRecording()
            resetVisualState()
            return
        }

        isProcessing = true
        scheduleStopWatchdog(for: attemptId)

        AudioFeedbackService.shared.play(.dictationStop)
        voiceInput?.stopRecording()
    }

    // MARK: - Transcript Processing

    private func handleTranscript(_ rawTranscript: String, attemptId: UUID) {
        Log.voice.info("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] handleTranscript, length=\(rawTranscript.count, privacy: .public)")
        guard isAttemptActive(attemptId) else { return }

        cancelStopWatchdog()

        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleFailure("No speech detected.", attemptId: attemptId)
            return
        }

        let cleanedText = TranscriptPostProcessor.process(rawTranscript)

        guard let store = conversationStore, let bridge = agentBridge else {
            Log.voice.error("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] missing dependencies")
            completeAttemptIfActive(attemptId)
            resetVisualState()
            return
        }

        // Create a new conversation and send the dictated text as a chat message.
        store.startNewConversation()
        let conversation = store.createConversation()
        let conversationId = conversation.id
        store.openConversation(id: conversationId)

        // Ensure the island is expanded so the user sees the agent working.
        if let screenCapture {
            IslandWindowManager.shared.showIsland(
                conversationStore: store,
                agentBridge: bridge,
                screenCapture: screenCapture
            )
        }
        IslandWindowManager.shared.expand()

        // Post notification to open the conversation in the island UI.
        NotificationCenter.default.post(
            name: .islandOpenConversationRequested,
            object: nil,
            userInfo: [NotificationPayloadKey.conversationId: conversationId.uuidString]
        )

        // Add the user message and send to the agent bridge.
        store.addMessage(to: conversationId, role: .user, content: cleanedText)
        store.setConversationRunning(conversationId, isRunning: true)
        bridge.sendChatMessage(
            conversationId: conversationId.uuidString,
            content: cleanedText,
            modelSpec: nil
        )

        AudioFeedbackService.shared.play(.dictationSuccess)
        Log.voice.info("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] completed — sent to agent")

        completeAttemptIfActive(attemptId)
        resetVisualState()
    }

    private func handleFailure(_ reason: String, attemptId: UUID) {
        guard isAttemptActive(attemptId) else { return }

        cancelStopWatchdog()

        if voiceInput?.isRecording == true {
            voiceInput?.stopRecording()
        }

        Log.voice.error("[dictation-to-agent \(attemptId.uuidString, privacy: .public)] failed: \(reason, privacy: .public)")
        IslandWindowManager.shared.showDictationNotification("Dictation failed: \(reason)")

        completeAttemptIfActive(attemptId)
        isDictating = false
        resetVisualState()
    }

    // MARK: - Helpers

    private func handleLevelPollTick() {
        if !Self.isHotkeyHeldGlobally(),
           (isDictating || voiceInput?.isRecording == true) {
            endDictation()
            return
        }

        if (isDictating || voiceInput?.isRecording == true),
           let start = recordingStartTime,
           Date().timeIntervalSince(start) >= maxContinuousRecordingDuration {
            endDictation()
            return
        }

        let levels = audioLevelMeter.currentLevels()
        barLevels = levels.bars
    }

    private func startModifierPolling() {
        stopModifierPolling()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            let held = Self.isHotkeyHeldGlobally()
            Task { @MainActor [weak self] in
                self?.updateModifierState(isHeld: held)
            }
        }
        timer.resume()
        modifierPollTimer = timer
    }

    private func stopModifierPolling() {
        modifierPollTimer?.cancel()
        modifierPollTimer = nil
    }

    private func scheduleStopWatchdog(for attemptId: UUID) {
        cancelStopWatchdog()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFailure("Timed out waiting for transcription.", attemptId: attemptId)
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
        return flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
    }

    private func selectedEngine() -> VoiceInputMode {
        let engine = UserDefaults.standard.string(forKey: "dictationEngine") ?? "apple"
        switch engine {
        case "parakeet":
            guard ParakeetModelManager.shared.isReady else { return .live }
            return .parakeetOnDevice
        default:
            return .live
        }
    }
}
