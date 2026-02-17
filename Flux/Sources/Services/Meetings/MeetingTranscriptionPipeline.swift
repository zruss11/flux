import Foundation
import MLXAudioVAD

@MainActor
final class MeetingTranscriptionPipeline {
    static let shared = MeetingTranscriptionPipeline()

    private let diarizationService: MeetingDiarizationService

    private init(diarizationService: MeetingDiarizationService = .shared) {
        self.diarizationService = diarizationService
    }

    func utterances(
        from transcript: String,
        duration: TimeInterval,
        pcmData: Data?
    ) async -> [MeetingUtterance] {
        let fallback = fallbackUtterances(from: transcript, duration: duration)
        guard let pcmData, !pcmData.isEmpty else { return fallback }
        guard ParakeetModelManager.shared.isReady else { return fallback }

        do {
            let segments = try await diarizationService.diarize(pcmData: pcmData)
            guard !segments.isEmpty else { return fallback }

            let perSpeaker = try transcribeSegments(segments, pcmData: pcmData)
            return perSpeaker.isEmpty ? fallback : perSpeaker
        } catch {
            Log.voice.error("Meeting diarization pipeline failed: \(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    private func transcribeSegments(
        _ segments: [DiarizationSegment],
        pcmData: Data
    ) throws -> [MeetingUtterance] {
        let bytesPerSample = MemoryLayout<Int16>.size
        let sampleRate = 16000.0
        let totalSamples = pcmData.count / bytesPerSample

        let transcriber = ParakeetTranscriber()
        let modelManager = ParakeetModelManager.shared

        var utterances: [MeetingUtterance] = []
        utterances.reserveCapacity(segments.count)

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let rawStart = max(0, Int(Double(segment.start) * sampleRate))
            let rawEnd = min(totalSamples, Int(Double(segment.end) * sampleRate))
            guard rawEnd > rawStart else { continue }

            let startByte = rawStart * bytesPerSample
            let endByte = rawEnd * bytesPerSample
            guard endByte > startByte else { continue }

            let segmentData = pcmData.subdata(in: startByte..<endByte)
            guard !segmentData.isEmpty else { continue }

            let rawText = try transcriber.transcribe(pcmData: segmentData, modelManager: modelManager)
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            utterances.append(
                MeetingUtterance(
                    speakerIndex: max(segment.speaker, 0),
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    text: text
                )
            )
        }

        return utterances
    }

    private func fallbackUtterances(from transcript: String, duration: TimeInterval) -> [MeetingUtterance] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return [
            MeetingUtterance(
                speakerIndex: 0,
                startTime: 0,
                endTime: max(duration, 0),
                text: trimmed
            )
        ]
    }
}
