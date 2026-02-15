@preconcurrency import AVFoundation
import AppKit
import Foundation
import os
import Speech

/// Continuously listens for a configurable wake phrase (e.g. "Hey Flux") using
/// on-device `SFSpeechRecognizer`, then triggers voice recording and sends the
/// transcribed command as a chat message.
@Observable
@MainActor
final class WakeWordDetector {

    static let shared = WakeWordDetector()

    // MARK: - Public State

    enum State: Sendable {
        case idle
        case listening
        case activated
        case recording
        case processing
    }

    private(set) var state: State = .idle

    var isEnabled: Bool { state != .idle }

    // MARK: - Configuration

    var wakePhrase: String {
        UserDefaults.standard.string(forKey: "wakePhrase") ?? "Hey Flux"
    }

    var silenceTimeout: TimeInterval {
        UserDefaults.standard.double(forKey: "handsFreesilenceTimeout").clamped(to: 0.5...5.0, default: 1.5)
    }

    // MARK: - Dependencies

    private var voiceInput: VoiceInput?
    private var conversationStore: ConversationStore?
    private var agentBridge: AgentBridge?

    // MARK: - Audio & Recognition (listening phase)

    private var listenEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer? = {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        return recognizer
    }()

    private var rollingRestartTimer: Timer?

    // MARK: - VAD (recording phase)

    private let audioLevelMeter = AudioLevelMeter()
    private let vad = VoiceActivityDetector()
    private var recordingTimeoutTask: Task<Void, Never>?

    // MARK: - Cooldown

    private var lastActivationTime: Date?
    private static let cooldownInterval: TimeInterval = 2.0

    private var consecutiveErrors = 0
    private static let maxConsecutiveErrors = 5

    // MARK: - Suspended state

    private var isSuspended = false

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    func start(
        voiceInput: VoiceInput,
        conversationStore: ConversationStore,
        agentBridge: AgentBridge
    ) {
        guard state == .idle else { return }

        self.voiceInput = voiceInput
        self.conversationStore = conversationStore
        self.agentBridge = agentBridge

        // Coordinate with push-to-talk: suspend while PTT is active.
        voiceInput.onRecordingStateChanged = { [weak self] isRecording in
            guard let self else { return }
            if isRecording && self.state == .listening {
                self.suspendListening()
            } else if !isRecording && self.isSuspended {
                self.resumeListening()
            }
        }

        beginListening()
    }

    func stop() {
        if state == .recording {
            voiceInput?.stopRecording()
        }
        tearDownListening()
        tearDownRecording()
        state = .idle
        isSuspended = false
        voiceInput?.onRecordingStateChanged = nil
        voiceInput = nil
        conversationStore = nil
        agentBridge = nil
    }

    func suspend() {
        guard state == .listening else { return }
        suspendListening()
    }

    func resume() {
        guard isSuspended else { return }
        resumeListening()
    }

    // MARK: - Listening Phase

    private func beginListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            Log.wakeWord.error("SFSpeechRecognizer not available")
            state = .idle
            return
        }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .authorized:
            break
        case .notDetermined:
            state = .idle
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.voiceInput != nil else { return }
                    if status == .authorized {
                        self.beginListening()
                    } else {
                        Log.wakeWord.error("Speech recognition authorization denied")
                        self.state = .idle
                    }
                }
            }
            return
        default:
            Log.wakeWord.error("Speech recognition authorization denied")
            state = .idle
            return
        }

        let engine = AVAudioEngine()
        self.listenEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            Log.wakeWord.error("No audio input available for wake word listening")
            state = .idle
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            state = .listening
            isSuspended = false
            Log.wakeWord.info("Wake word listening started — phrase: \(self.wakePhrase, privacy: .public)")
        } catch {
            Log.wakeWord.error("Failed to start listen engine: \(error)")
            tearDownListening()
            state = .idle
            return
        }

        // Rolling restart to avoid Apple's ~60s recognition timeout.
        scheduleRollingRestart()
    }

    private func scheduleRollingRestart() {
        rollingRestartTimer?.invalidate()
        rollingRestartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                Log.wakeWord.debug("Rolling restart of recognition session")
                self.tearDownListening()
                self.beginListening()
            }
        }
    }

    private func tearDownListening() {
        rollingRestartTimer?.invalidate()
        rollingRestartTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        listenEngine?.stop()
        listenEngine?.inputNode.removeTap(onBus: 0)
        listenEngine = nil
    }

    private func suspendListening() {
        guard state == .listening else { return }
        isSuspended = true
        tearDownListening()
        Log.wakeWord.info("Wake word listening suspended")
    }

    private func resumeListening() {
        guard isSuspended else { return }
        isSuspended = false
        beginListening()
        Log.wakeWord.info("Wake word listening resumed")
    }

    // MARK: - Recognition Result Handling

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard state == .listening else { return }

        if let error {
            consecutiveErrors += 1
            Log.wakeWord.debug("Recognition error (\(self.consecutiveErrors)/\(Self.maxConsecutiveErrors)): \(error.localizedDescription)")

            if consecutiveErrors >= Self.maxConsecutiveErrors {
                Log.wakeWord.error("Too many consecutive recognition errors — disabling wake word")
                tearDownListening()
                state = .idle
                return
            }

            // Restart listening on transient errors.
            tearDownListening()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if self.state != .idle && !self.isSuspended {
                    self.beginListening()
                }
            }
            return
        }

        guard let result else { return }
        consecutiveErrors = 0

        let transcript = result.bestTranscription.formattedString
        let normalizedTranscript = transcript.lowercased()
        let normalizedPhrase = wakePhrase.lowercased()

        guard normalizedTranscript.contains(normalizedPhrase) else { return }

        // Cooldown check to prevent double-triggers.
        if let lastTime = lastActivationTime,
           Date().timeIntervalSince(lastTime) < Self.cooldownInterval {
            return
        }

        Log.wakeWord.info("Wake phrase detected in: \(transcript, privacy: .public)")
        lastActivationTime = Date()
        activateRecording(triggerTranscript: transcript)
    }

    // MARK: - Activation & Recording Phase

    private func activateRecording(triggerTranscript: String) {
        state = .activated
        tearDownListening()

        // Play activation sound.
        NSSound.beep()

        state = .recording

        guard let voiceInput else {
            Log.wakeWord.error("No VoiceInput available for recording")
            returnToListening()
            return
        }

        voiceInput.audioLevelMeter = audioLevelMeter

        Task {
            let permitted = await voiceInput.ensureMicrophonePermission()
            guard permitted else {
                Log.wakeWord.warning("Microphone permission not granted")
                returnToListening()
                return
            }

            // Start silence-based auto-stop.
            vad.startMonitoring(
                meter: audioLevelMeter,
                silenceThreshold: 0.01,
                silenceDuration: silenceTimeout
            ) { [weak self] in
                guard let self, self.state == .recording else { return }
                Log.wakeWord.info("Silence detected — stopping recording")
                self.voiceInput?.stopRecording()
            }

            // Max recording timeout (30s).
            recordingTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.state == .recording else { return }
                Log.wakeWord.info("Max recording duration reached — stopping recording")
                self.voiceInput?.stopRecording()
            }

            await voiceInput.startRecording(
                mode: .batchOnDevice,
                onComplete: { [weak self] transcript in
                    self?.handleCommandTranscript(transcript)
                }
            )
        }
    }

    private func tearDownRecording() {
        vad.stopMonitoring()
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil
        audioLevelMeter.reset()
    }

    // MARK: - Processing Phase

    private func handleCommandTranscript(_ rawTranscript: String) {
        guard state != .idle else {
            Log.wakeWord.debug("Ignoring transcript because wake word is disabled")
            return
        }
        state = .processing
        tearDownRecording()

        var text = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip wake phrase prefix if the recognizer captured it.
        let phrasePattern = wakePhrase.lowercased()
        if text.lowercased().hasPrefix(phrasePattern) {
            text = String(text.dropFirst(phrasePattern.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Also strip common trailing punctuation/comma after the wake phrase.
            if text.hasPrefix(",") || text.hasPrefix(".") {
                text = String(text.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !text.isEmpty else {
            Log.wakeWord.info("Empty transcript after stripping wake phrase — returning to listening")
            returnToListening()
            return
        }

        // Clean filler words.
        let cleanedText = FillerWordCleaner.clean(text)

        Log.wakeWord.info("Sending hands-free command: \(cleanedText, privacy: .public)")
        sendAsMessage(cleanedText)
    }

    private func sendAsMessage(_ text: String) {
        guard let conversationStore, let agentBridge else {
            Log.wakeWord.error("Missing conversationStore or agentBridge")
            returnToListening()
            return
        }

        guard agentBridge.isConnected else {
            Log.wakeWord.warning("Agent bridge not connected — cannot send message")
            returnToListening()
            return
        }

        let conversationId: UUID
        if let activeId = conversationStore.activeConversationId {
            conversationId = activeId
        } else {
            conversationId = conversationStore.createConversation().id
        }

        conversationStore.addMessage(to: conversationId, role: .user, content: text)
        conversationStore.setConversationRunning(conversationId, isRunning: true)

        agentBridge.sendChatMessage(
            conversationId: conversationId.uuidString,
            content: text
        )

        // Expand the island to show the conversation.
        if !IslandWindowManager.shared.isShown, let voiceInput {
            IslandWindowManager.shared.showIsland(
                conversationStore: conversationStore,
                agentBridge: agentBridge,
                screenCapture: ScreenCapture(),
                voiceInput: voiceInput
            )
        }
        conversationStore.openConversation(id: conversationId)
        IslandWindowManager.shared.expand()

        returnToListening()
    }

    // MARK: - State Transitions

    private func returnToListening() {
        tearDownRecording()
        beginListening()
    }
}

// MARK: - Double extension

private extension Double {
    func clamped(to range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        let value = self == 0 ? defaultValue : self
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
