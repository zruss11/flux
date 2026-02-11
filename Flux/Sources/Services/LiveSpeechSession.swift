@preconcurrency import AVFoundation
import Foundation
import os
import Speech

@available(macOS 26.0, *)
@MainActor
final class LiveSpeechSession {
    // AsyncStream continuation is safe to yield from any thread, but we still avoid
    // crossing actor isolation by storing it behind a lock.
    final class Feeder: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: AsyncStream<AnalyzerInput>.Continuation?.none)

        func setContinuation(_ continuation: AsyncStream<AnalyzerInput>.Continuation) {
            lock.withLock { $0 = continuation }
        }

        func yield(_ input: AnalyzerInput) {
            _ = lock.withLock { $0?.yield(input) }
        }

        func finish() {
            lock.withLock {
                $0?.finish()
                $0 = nil
            }
        }
    }

    let feeder = Feeder()
    private(set) var analyzerFormat: AVAudioFormat

    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var resultsTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?

    private var finalized = ""
    private var volatile = ""
    private let onTranscriptUpdate: @MainActor (String) -> Void

    init(
        inputFormat: AVAudioFormat,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) throws {
        self.onTranscriptUpdate = onTranscriptUpdate

        // Emit partial (volatile) results for live UI updates.
        transcriber = SpeechTranscriber(
            locale: Locale.current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        analyzer = SpeechAnalyzer(modules: [transcriber])
        analyzerFormat = inputFormat
    }

    func prepare() async {
        // Let the system choose the best format for on-device speech models.
        if let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
            analyzerFormat = format
        }
    }

    func start() {
        let inputSequence = AsyncStream<AnalyzerInput> { continuation in
            feeder.setContinuation(continuation)
        }

        analyzerTask = Task { [analyzer] in
            do {
                try await analyzer.start(inputSequence: inputSequence)
            } catch {
                // If analysis fails, we still want to stop cleanly.
            }
        }

        resultsTask = Task { [transcriber] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        volatile = ""
                    } else {
                        volatile = text
                    }

                    let combined = (finalized + volatile)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    onTranscriptUpdate(combined)
                }
            } catch {
                // Best effort.
            }
        }
    }

    @MainActor
    func stop() async -> String {
        feeder.finish()

        // Wait for the results task to finish naturally (the stream should end
        // once the analyzer drains), but cap at 1.5 s so we never hang.
        _ = await withTaskGroup(of: Void.self) { group in
            group.addTask { [resultsTask] in
                await resultsTask?.value
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(1500))
            }
            // Whichever finishes first unblocks us.
            await group.next()
            group.cancelAll()
        }

        analyzerTask?.cancel()
        resultsTask?.cancel()

        let combined = (finalized + volatile)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return combined
    }

    // MARK: - Tap block

    nonisolated static func makeTapBlock(
        analyzerFormat: AVAudioFormat,
        converter: AVAudioConverter?,
        feeder: Feeder,
        meter: AudioLevelMeter?
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            meter?.update(from: buffer)

            // Convert to analyzer format if necessary.
            let outputBuffer: AVAudioPCMBuffer

            if let converter, buffer.format != analyzerFormat {
                let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
                let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: frameCapacity) else {
                    return
                }

                var error: NSError?
                let status = converter.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard status != .error, error == nil else { return }
                outputBuffer = converted
            } else {
                outputBuffer = buffer
            }

            feeder.yield(AnalyzerInput(buffer: outputBuffer))
        }
    }
}
