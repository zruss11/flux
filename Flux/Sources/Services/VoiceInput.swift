import Speech
import AVFoundation

@Observable
@MainActor
final class VoiceInput {
    var isRecording = false
    var transcript = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var onComplete: ((String) -> Void)?

    var isPermissionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording(onComplete: @escaping (String) -> Void) {
        guard !isRecording else { return }
        self.onComplete = onComplete

        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.finishRecording()
                    }
                }

                if error != nil {
                    self.finishRecording()
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            transcript = ""
        } catch {
            print("Audio engine start error: \(error)")
            finishRecording()
        }
    }

    func stopRecording() {
        recognitionRequest?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
    }

    private func finishRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isRecording = false

        if !transcript.isEmpty {
            onComplete?(transcript)
        }
        onComplete = nil
    }
}
