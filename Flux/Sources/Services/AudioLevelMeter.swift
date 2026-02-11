import AVFoundation
import Foundation
import os

final class AudioLevelMeter: @unchecked Sendable {

    private struct Levels: Sendable {
        var rms: Float = 0
        var bars: [Float] = Array(repeating: 0, count: 16)
    }

    private let lock = OSAllocatedUnfairLock(initialState: Levels())

    private static let barCount = 16
    private static let smoothingAlpha: Float = 0.3

    func update(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples = channelData[0]

        // Overall RMS
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            let s = samples[i]
            sumOfSquares += s * s
        }
        let rms = sqrtf(sumOfSquares / Float(frameCount))

        // Per-segment RMS (16 bars)
        let segmentSize = max(1, frameCount / Self.barCount)
        let newBars: [Float] = (0..<Self.barCount).map { bar in
            let start = bar * segmentSize
            let end = min((bar == Self.barCount - 1) ? frameCount : start + segmentSize, frameCount)
            guard end > start else { return Float(0) }
            var segSum: Float = 0
            for i in start..<end {
                let s = samples[i]
                segSum += s * s
            }
            return sqrtf(segSum / Float(end - start))
        }

        // Apply exponential moving average
        let alpha = Self.smoothingAlpha
        lock.withLock { state in
            state.rms = alpha * rms + (1 - alpha) * state.rms
            for i in 0..<Self.barCount {
                state.bars[i] = alpha * newBars[i] + (1 - alpha) * state.bars[i]
            }
        }
    }

    func currentLevels() -> (rms: Float, bars: [Float]) {
        lock.withLock { (rms: $0.rms, bars: $0.bars) }
    }

    func reset() {
        lock.withLock { $0 = Levels() }
    }
}
