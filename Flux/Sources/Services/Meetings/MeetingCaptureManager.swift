import Foundation

@Observable
@MainActor
final class MeetingCaptureManager {
    static let shared = MeetingCaptureManager()

    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var activeMeetingId: UUID?
    private(set) var lastError: String?

    var liveTranscript: String {
        voiceInput?.transcript ?? ""
    }

    private var voiceInput: VoiceInput?
    private var recordingStartedAt: Date?

    private let meetingStore: MeetingStore
    private let transcriptionPipeline: MeetingTranscriptionPipeline

    private init(
        meetingStore: MeetingStore = .shared,
        transcriptionPipeline: MeetingTranscriptionPipeline = .shared
    ) {
        self.meetingStore = meetingStore
        self.transcriptionPipeline = transcriptionPipeline
    }

    @discardableResult
    func startMeeting(title: String? = nil) async -> Bool {
        guard !isRecording else { return false }

        let input = VoiceInput()
        let hasMicPermission = await input.ensureMicrophonePermission()
        guard hasMicPermission else {
            lastError = "Microphone permission not granted."
            return false
        }

        guard ParakeetModelManager.shared.isReady else {
            lastError = "Parakeet models are not loaded. Download models in Settings → Voice & Transcription."
            return false
        }

        let meeting = meetingStore.createMeeting(title: title)
        activeMeetingId = meeting.id
        isRecording = true
        isProcessing = false
        lastError = nil
        recordingStartedAt = Date()
        voiceInput = input

        let started = await input.startRecording(
            mode: .parakeetOnDevice,
            onComplete: { [weak self] transcript in
                Task { @MainActor [weak self] in
                    await self?.handleMeetingTranscript(transcript)
                }
            },
            onFailure: { [weak self] reason in
                self?.lastError = reason
                self?.handleFailure()
            }
        )

        if !started {
            meetingStore.markMeetingFailed(id: meeting.id)
            if lastError == nil {
                lastError = "Unable to start meeting capture."
            }
            resetState()
            return false
        }

        return true
    }

    func stopMeeting() {
        guard isRecording else { return }

        if let meetingId = activeMeetingId,
           var meeting = meetingStore.meeting(id: meetingId),
           meeting.status == .recording {
            meeting.status = .processing
            meetingStore.updateMeeting(meeting)
        }

        isProcessing = true
        voiceInput?.stopRecording()
    }

    private func handleMeetingTranscript(_ transcript: String) async {
        guard let meetingId = activeMeetingId else {
            resetState()
            return
        }

        isProcessing = true

        let duration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        let pcmData = voiceInput?.lastCapturedPCMData
        let utterances = await transcriptionPipeline.utterances(
            from: transcript,
            duration: duration,
            pcmData: pcmData
        )

        for utterance in utterances {
            meetingStore.appendUtterance(utterance, to: meetingId)
        }

        if utterances.isEmpty {
            lastError = "No speech detected in this recording."
            meetingStore.markMeetingFailed(id: meetingId)
        } else {
            lastError = nil
            meetingStore.finishMeeting(id: meetingId, status: .completed)
        }

        resetState()
    }

    private func handleFailure() {
        if lastError == nil {
            lastError = "Meeting capture failed."
        }

        if let meetingId = activeMeetingId {
            meetingStore.markMeetingFailed(id: meetingId)
        }
        resetState()
    }

    private func resetState() {
        voiceInput = nil
        recordingStartedAt = nil
        activeMeetingId = nil
        isRecording = false
        isProcessing = false
    }
}
