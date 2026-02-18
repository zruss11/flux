import Foundation
@preconcurrency import MLX
import MLXAudioVAD

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

actor MeetingDiarizationService {
    static let shared = MeetingDiarizationService()

    private let modelRepo = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    private var model: SortformerModel?

    private init() {}

    func diarize(
        pcmData: Data,
        sampleRate: Int = 16000,
        threshold: Float = 0.5,
        minDuration: Float = 0.25,
        mergeGap: Float = 0.35
    ) async throws -> [DiarizationSegment] {
        guard !pcmData.isEmpty else { return [] }

        let loadedModel = try await loadModelIfNeeded()

        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        var samples = [Float]()
        samples.reserveCapacity(sampleCount)

        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for value in int16Buffer {
                samples.append(Float(value) / Float(Int16.max))
            }
        }

        let modelBox = UnsafeSendable(value: loadedModel)
        let audioBox = UnsafeSendable(value: MLXArray(samples))

        let result = try await Task.detached(priority: .userInitiated) {
            try await modelBox.value.generate(
                audio: audioBox.value,
                sampleRate: sampleRate,
                threshold: threshold,
                minDuration: minDuration,
                mergeGap: mergeGap,
                verbose: false
            )
        }.value

        return result.segments
    }

    private func loadModelIfNeeded() async throws -> SortformerModel {
        if let model {
            return model
        }

        let loaded = try await SortformerModel.fromPretrained(modelRepo)
        model = loaded
        return loaded
    }
}
