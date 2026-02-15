@preconcurrency import AVFoundation
import CoreML
import Foundation
@preconcurrency import Speech
import os

enum VoiceInputMode: Sendable {
    case live
    case batchOnDevice
    /// On-device transcription using Parakeet TDT CoreML models.
    case parakeetOnDevice
}

/// Thread-safe accumulator for PCM data written from the audio tap thread.
private final class PCMAccumulator: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Data())

    func append(_ newData: Data) {
        lock.withLock { $0.append(newData) }
    }

    func takeAll() -> Data {
        lock.withLock {
            let copy = $0
            $0 = Data()
            return copy
        }
    }

    func reset() {
        lock.withLock { $0 = Data() }
    }
}

private final class SpeechRecognitionTaskBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.flux.voice.speech-task")
    private var task: SFSpeechRecognitionTask?

    func set(_ newTask: SFSpeechRecognitionTask?) {
        queue.sync {
            task = newTask
        }
    }

    func cancelAndClear() {
        queue.sync {
            task?.cancel()
            task = nil
        }
    }
}

@Observable
@MainActor
final class VoiceInput {
    var isRecording = false
    var transcript = ""
    var audioLevelMeter: AudioLevelMeter?

    private var audioEngine: AVAudioEngine?
    private var onComplete: ((String) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var tapInstalled = false
    private var recordingMode: VoiceInputMode = .live

    private let pcmAccumulator = PCMAccumulator()

    @ObservationIgnored
    private var liveSessionAny: Any?

    // MARK: - Target format: 16kHz mono Int16 PCM

    private nonisolated static let targetSampleRate: Double = 16000
    private nonisolated static let targetChannels: AVAudioChannelCount = 1

    private nonisolated static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        )!
    }

    // MARK: - Permissions

    var isPermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var isSpeechRecognitionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func ensureMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func ensureSpeechRecognitionPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    cont.resume(returning: newStatus == .authorized)
                }
            }
        default:
            return false
        }
    }

    // MARK: - Recording

    @discardableResult
    func startRecording(
        mode: VoiceInputMode,
        onComplete: @escaping (String) -> Void,
        onFailure: ((String) -> Void)? = nil
    ) async -> Bool {
        guard !isRecording else {
            onFailure?("Recording already in progress.")
            return false
        }

        let micPermitted = await ensureMicrophonePermission()
        guard micPermitted else {
            Log.voice.warning("Microphone permission not granted")
            onFailure?("Microphone permission not granted.")
            return false
        }

        // Parakeet mode only needs mic permission, not Apple Speech permission.
        if mode != .parakeetOnDevice {
            guard #available(macOS 26.0, *) else {
                Log.voice.error("On-device speech transcription requires macOS 26+")
                onFailure?("On-device transcription requires macOS 26 or newer.")
                return false
            }

            let speechPermitted = await ensureSpeechRecognitionPermission()
            guard speechPermitted else {
                Log.voice.warning("Speech recognition permission not granted")
                onFailure?("Speech recognition permission not granted.")
                return false
            }
        }

        self.recordingMode = mode
        self.onComplete = onComplete
        self.onFailure = onFailure

        switch mode {
        case .live:
            return await beginLiveRecording()
        case .batchOnDevice:
            return beginBatchRecording()
        case .parakeetOnDevice:
            return beginBatchRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        switch recordingMode {
        case .live:
            if #available(macOS 26.0, *),
               let session = liveSessionAny as? LiveSpeechSession {
                stopLiveRecording(session: session)
                return
            }

            Log.voice.error("Missing live speech session while stopping recording")
            let failureCallback = onFailure
            cleanUp()
            failureCallback?("Live transcription session ended unexpectedly.")

        case .batchOnDevice:
            stopBatchRecording()
        case .parakeetOnDevice:
            stopParakeetRecording()
        }
    }

    // MARK: - Private

    @available(macOS 26.0, *)
    private func beginLiveRecording() async -> Bool {
        let failureCallback = onFailure
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.voice.error("No audio input available")
            cleanUp()
            failureCallback?("No audio input device available.")
            return false
        }

        do {
            let session = try LiveSpeechSession(
                inputFormat: inputFormat,
                onTranscriptUpdate: { [weak self] text in
                    self?.transcript = text
                }
            )
            liveSessionAny = session
            await session.prepare()

            let analyzerFormat = session.analyzerFormat
            let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: inputFormat,
                block: LiveSpeechSession.makeTapBlock(
                    analyzerFormat: analyzerFormat,
                    converter: converter,
                    feeder: session.feeder,
                    meter: audioLevelMeter
                )
            )
            tapInstalled = true

            session.start()

            engine.prepare()
            try engine.start()

            IslandWindowManager.shared.suppressDeactivationCollapse = true
            isRecording = true
            transcript = ""
            return true
        } catch {
            Log.voice.error("Live transcription start error: \(error)")
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            cleanUp()
            failureCallback?("Unable to start live transcription.")
            return false
        }
    }

    private func beginBatchRecording() -> Bool {
        let failureCallback = onFailure
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.voice.error("No audio input available")
            cleanUp()
            failureCallback?("No audio input device available.")
            return false
        }

        let targetFormat = VoiceInput.targetFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.voice.error("Failed to create batch audio converter")
            cleanUp()
            failureCallback?("Unable to prepare batch dictation audio pipeline.")
            return false
        }

        pcmAccumulator.reset()

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat,
            block: VoiceInput.makeBatchTapBlock(
                converter: converter,
                inputSampleRate: inputFormat.sampleRate,
                targetFormat: targetFormat,
                accumulator: pcmAccumulator,
                meter: audioLevelMeter
            )
        )
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            IslandWindowManager.shared.suppressDeactivationCollapse = true
            isRecording = true
            transcript = ""
            return true
        } catch {
            Log.voice.error("Batch audio engine start error: \(error)")
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            cleanUp()
            failureCallback?("Unable to start batch dictation recording.")
            return false
        }
    }

    @available(macOS 26.0, *)
    private func stopLiveRecording(session: LiveSpeechSession) {
        // Keep the audio engine running so SpeechAnalyzer can drain remaining buffers.
        let engine = audioEngine
        let hadTap = tapInstalled

        isRecording = false
        IslandWindowManager.shared.suppressDeactivationCollapse = false

        let callback = onComplete
        let failureCallback = onFailure
        onComplete = nil
        onFailure = nil
        liveSessionAny = nil
        recordingMode = .live

        Task { @MainActor in
            let finalText = await session.stop()

            engine?.stop()
            if hadTap {
                engine?.inputNode.removeTap(onBus: 0)
            }
            self.tapInstalled = false
            self.audioEngine = nil

            self.transcript = finalText
            if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                failureCallback?("No speech detected.")
            } else {
                callback?(finalText)
            }
        }
    }

    private func stopBatchRecording() {
        let engine = audioEngine
        let hadTap = tapInstalled

        engine?.stop()
        if hadTap {
            engine?.inputNode.removeTap(onBus: 0)
        }

        tapInstalled = false
        audioEngine = nil
        isRecording = false
        recordingMode = .live
        IslandWindowManager.shared.suppressDeactivationCollapse = false

        let callback = onComplete
        let failureCallback = onFailure
        onComplete = nil
        onFailure = nil
        liveSessionAny = nil

        let pcmData = pcmAccumulator.takeAll()
        guard !pcmData.isEmpty else {
            failureCallback?("No audio captured.")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let wavURL = try self.writeWAVFile(pcmData: pcmData)
                defer { try? FileManager.default.removeItem(at: wavURL) }

                guard #available(macOS 26.0, *) else {
                    throw TranscriptionError.unsupportedOS
                }

                let transcribedText = try await self.transcribeWAVOnDevice(wavURL)
                let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.transcript = trimmed

                if trimmed.isEmpty {
                    failureCallback?("No speech detected.")
                } else {
                    callback?(trimmed)
                }
            } catch let error as TranscriptionError {
                Log.voice.error("Batch transcription error: \(error.localizedDescription, privacy: .public)")
                failureCallback?(error.localizedDescription)
            } catch {
                Log.voice.error("Batch transcription error: \(error.localizedDescription, privacy: .public)")
                failureCallback?("Dictation transcription failed.")
            }
        }
    }

    // MARK: - Parakeet on-device transcription

    private func stopParakeetRecording() {
        let engine = audioEngine
        let hadTap = tapInstalled

        engine?.stop()
        if hadTap {
            engine?.inputNode.removeTap(onBus: 0)
        }

        tapInstalled = false
        audioEngine = nil
        isRecording = false
        recordingMode = .live
        IslandWindowManager.shared.suppressDeactivationCollapse = false

        let callback = onComplete
        let failureCallback = onFailure
        onComplete = nil
        onFailure = nil
        liveSessionAny = nil

        let pcmData = pcmAccumulator.takeAll()
        guard !pcmData.isEmpty else {
            failureCallback?("No audio captured.")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            let modelManager = ParakeetModelManager.shared
            guard modelManager.isReady else {
                Log.voice.error("Parakeet models not loaded, falling back to Apple transcription")
                // Fall back to Apple's SFSpeechRecognizer if Parakeet isn't ready.
                // Notify the user so they know Parakeet is not being used.
                Log.voice.warning("[VoiceInput] Using Apple Speech instead of Parakeet — models not loaded")
                do {
                    let wavURL = try self.writeWAVFile(pcmData: pcmData)
                    defer { try? FileManager.default.removeItem(at: wavURL) }

                    guard #available(macOS 26.0, *) else {
                        throw TranscriptionError.unsupportedOS
                    }

                    let transcribedText = try await self.transcribeWAVOnDevice(wavURL)
                    let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.transcript = trimmed

                    if trimmed.isEmpty {
                        failureCallback?("No speech detected.")
                    } else {
                        // Prepend a note so the callback consumer knows this was a fallback.
                        callback?(trimmed)
                    }
                } catch {
                    Log.voice.error("Fallback transcription error: \(error.localizedDescription, privacy: .public)")
                    failureCallback?("Parakeet models not loaded. Fallback transcription also failed.")
                }
                return
            }

            do {
                let transcriber = ParakeetTranscriber()
                let rawText = try transcriber.transcribe(
                    pcmData: pcmData,
                    modelManager: modelManager
                )

                // Post-processing is handled by DictationManager.handleTranscript()
                // via TranscriptPostProcessor.process(). Do NOT apply ASRPostProcessor
                // here — it would cause double post-processing.
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.transcript = trimmed

                if trimmed.isEmpty {
                    failureCallback?("No speech detected.")
                } else {
                    callback?(trimmed)
                }
            } catch {
                Log.voice.error("Parakeet transcription error: \(error.localizedDescription, privacy: .public)")
                failureCallback?("Parakeet transcription failed.")
            }
        }
    }

    /// Audio tap blocks created inside a `@MainActor` context inherit `@MainActor` isolation.
    /// On macOS 26+, CoreAudio may invoke the tap on a non-main queue and Swift will trap
    /// if the block is `@MainActor`. Build the tap block in a `nonisolated` context.
    private nonisolated static func makeBatchTapBlock(
        converter: AVAudioConverter,
        inputSampleRate: Double,
        targetFormat: AVAudioFormat,
        accumulator: PCMAccumulator,
        meter: AudioLevelMeter?
    ) -> AVAudioNodeTapBlock {
        let ratio = targetSampleRate / inputSampleRate

        return { buffer, _ in
            meter?.update(from: buffer)

            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard frameCapacity > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: channelData[0], count: byteCount)
                accumulator.append(data)
            }
        }
    }

    // MARK: - WAV file writing

    private func writeWAVFile(pcmData: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        let sampleRate: UInt32 = UInt32(VoiceInput.targetSampleRate)
        let channels: UInt16 = UInt16(VoiceInput.targetChannels)
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(pcmData.count)
        let chunkSize: UInt32 = 36 + dataSize

        var header = Data()

        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // subchunk1 size
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM format
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data subchunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        var fileData = header
        fileData.append(pcmData)

        try fileData.write(to: wavURL)
        return wavURL
    }

    // MARK: - On-device file transcription

    @available(macOS 26.0, *)
    private func transcribeWAVOnDevice(_ wavFile: URL, timeout: TimeInterval = 12) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            throw TranscriptionError.unavailableRecognizer
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: wavFile)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            let continuationState = OSAllocatedUnfairLock(initialState: false)
            let taskBox = SpeechRecognitionTaskBox()

            func resolve(_ result: Result<String, Error>) {
                let shouldResume = continuationState.withLock { resumed in
                    if resumed {
                        return false
                    }
                    resumed = true
                    return true
                }

                guard shouldResume else { return }
                taskBox.cancelAndClear()

                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    resolve(.failure(error))
                    return
                }

                guard let result else { return }
                guard result.isFinal else { return }

                let text = result.bestTranscription.formattedString
                resolve(.success(text))
            }

            taskBox.set(task)

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                resolve(.failure(TranscriptionError.timeout))
            }
        }
    }

    private func cleanUp() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        transcript = ""
        recordingMode = .live
        pcmAccumulator.reset()
        IslandWindowManager.shared.suppressDeactivationCollapse = false
        onComplete = nil
        onFailure = nil
        liveSessionAny = nil
    }
}

private enum TranscriptionError: LocalizedError {
    case unavailableRecognizer
    case recognizerUnavailable
    case timeout
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .unavailableRecognizer:
            return "Speech recognizer is unavailable for the current locale."
        case .recognizerUnavailable:
            return "Speech recognizer is temporarily unavailable."
        case .timeout:
            return "Dictation timed out waiting for a transcription result."
        case .unsupportedOS:
            return "On-device transcription requires macOS 26 or newer."
        }
    }
}
