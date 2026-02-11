@preconcurrency import AVFoundation
import Foundation
import os
import Speech

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

@Observable
@MainActor
final class VoiceInput {
    var isRecording = false
    var transcript = ""
    var isTranscriberAvailable = false
    var audioLevelMeter: AudioLevelMeter?

    private var audioEngine: AVAudioEngine?
    private let pcmAccumulator = PCMAccumulator()
    private var onComplete: ((String) -> Void)?
    private var tapInstalled = false

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

    // MARK: - Transcriber health

    func checkTranscriberHealth() async {
        do {
            let url = URL(string: "http://localhost:7848/health")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 3
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                isTranscriberAvailable = httpResponse.statusCode == 200
            } else {
                isTranscriberAvailable = false
            }
        } catch {
            isTranscriberAvailable = false
        }
    }

    // MARK: - Recording

    func startRecording(onComplete: @escaping (String) -> Void) async {
        guard !isRecording else { return }

        let permitted = await ensureMicrophonePermission()
        guard permitted else {
            Log.voice.warning("Microphone permission not granted")
            return
        }

        self.onComplete = onComplete

        if #available(macOS 26.0, *) {
            // Prefer Apple's new on-device live transcription when available.
            let speechPermitted = await ensureSpeechRecognitionPermission()
            if speechPermitted, await beginLiveRecording() {
                return
            }
        }

        beginBatchRecording()
    }

    func stopRecording() {
        guard isRecording else { return }

        if #available(macOS 26.0, *), let session = liveSessionAny as? LiveSpeechSession {
            stopLiveRecording(session: session)
            return
        }

        audioEngine?.stop()
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isRecording = false
        IslandWindowManager.shared.suppressDeactivationCollapse = false

        let pcmData = pcmAccumulator.takeAll()
        audioEngine = nil

        guard !pcmData.isEmpty else {
            Log.voice.warning("No audio data recorded")
            cleanUp()
            return
        }

        let callback = onComplete
        onComplete = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let wavURL = try self.writeWAVFile(pcmData: pcmData)
                let transcribedText = try await self.transcribe(wavFile: wavURL)
                try? FileManager.default.removeItem(at: wavURL)

                self.transcript = transcribedText
                if !transcribedText.isEmpty {
                    callback?(transcribedText)
                }
            } catch {
                Log.voice.error("Transcription error: \(error)")
            }
        }
    }

    // MARK: - Private

    /// Audio tap blocks created inside a `@MainActor` context inherit `@MainActor` isolation.
    /// On macOS 26+, CoreAudio may invoke the tap on a non-main queue and Swift will trap
    /// if the block is `@MainActor`. Build the tap block in a `nonisolated` context.
    private nonisolated static func makeTapBlock(
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

    private func beginBatchRecording() {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.voice.error("No audio input available")
            cleanUp()
            return
        }

        let targetFmt = VoiceInput.targetFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFmt) else {
            Log.voice.error("Failed to create audio converter")
            cleanUp()
            return
        }

        pcmAccumulator.reset()

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat,
            block: VoiceInput.makeTapBlock(
                converter: converter,
                inputSampleRate: inputFormat.sampleRate,
                targetFormat: targetFmt,
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
        } catch {
            Log.voice.error("Audio engine start error: \(error)")
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            cleanUp()
        }
    }

    @available(macOS 26.0, *)
    private func beginLiveRecording() async -> Bool {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.voice.error("No audio input available")
            cleanUp()
            return false
        }

        do {
            let session = try LiveSpeechSession(
                inputFormat: inputFormat,
                onTranscriptUpdate: { [weak self] text in
                    self?.transcript = text
                }
            )
            self.liveSessionAny = session
            await session.prepare()

            // Audio format conversion for analyzer input (if needed).
            let analyzerFormat = session.analyzerFormat
            let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)

            // Feed analyzer input from the realtime tap thread. No actor hops.
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
            liveSessionAny = nil
            cleanUp()
            return false
        }
    }

    @available(macOS 26.0, *)
    private func stopLiveRecording(session: LiveSpeechSession) {
        // Keep the audio engine running so the transcriber can drain
        // any remaining audio buffers before we tear it down.
        let engine = audioEngine
        let hadTap = tapInstalled

        isRecording = false
        IslandWindowManager.shared.suppressDeactivationCollapse = false

        let callback = onComplete
        onComplete = nil
        liveSessionAny = nil

        Task { @MainActor in
            // session.stop() finishes the feeder stream and waits for the
            // transcriber to flush its final segment.
            let finalText = await session.stop()

            // NOW tear down the audio engine after the session has drained.
            engine?.stop()
            if hadTap {
                engine?.inputNode.removeTap(onBus: 0)
            }
            self.tapInstalled = false
            self.audioEngine = nil

            self.transcript = finalText
            if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                callback?(finalText)
            }
        }
    }

    private func cleanUp() {
        audioEngine = nil
        pcmAccumulator.reset()
        isRecording = false
        IslandWindowManager.shared.suppressDeactivationCollapse = false
        onComplete = nil
        liveSessionAny = nil
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

    // MARK: - Transcription via local parakeet server

    private func transcribe(wavFile: URL) async throws -> String {
        let wavData = try Data(contentsOf: wavFile)

        var request = URLRequest(url: URL(string: "http://localhost:7848/transcribe")!)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranscriptionError.serverError(statusCode: statusCode)
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text
    }
}

// MARK: - Supporting types

private struct TranscriptionResponse: Decodable {
    let text: String
}

private enum TranscriptionError: LocalizedError {
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let statusCode):
            return "Transcription server returned status \(statusCode)"
        }
    }
}
