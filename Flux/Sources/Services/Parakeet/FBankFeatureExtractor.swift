import Accelerate
import Foundation
import os

// MARK: - FBankFeatureExtractor

/// Extracts mel filter bank (FBank) features from raw PCM audio data.
///
/// This is a pure-Swift implementation using Apple's Accelerate framework for
/// efficient FFT computation. It produces log-mel spectrograms compatible with
/// Parakeet TDT models.
///
/// Configuration matches NVIDIA NeMo defaults:
/// - 80 mel filter banks
/// - 25ms window, 10ms hop
/// - 16kHz sample rate
/// - Pre-emphasis: 0.97
final class FBankFeatureExtractor: Sendable {

    // MARK: - Configuration

    let sampleRate: Int
    let numMelBins: Int
    let windowSizeMs: Double
    let hopSizeMs: Double
    let preEmphasis: Float
    let fftSize: Int

    /// Number of samples per analysis window.
    var windowSizeSamples: Int { Int(Double(sampleRate) * windowSizeMs / 1000.0) }

    /// Number of samples between consecutive windows.
    var hopSizeSamples: Int { Int(Double(sampleRate) * hopSizeMs / 1000.0) }

    /// Precomputed mel filter bank weights.
    private let melFilterBank: [[Float]]

    /// Precomputed Hann window.
    private let hannWindow: [Float]

    /// Cached FFT setup — created once and reused across all frames.
    private let fftSetup: OpaquePointer
    private let log2n: vDSP_Length

    // MARK: - Init

    init(
        sampleRate: Int = 16000,
        numMelBins: Int = 80,
        windowSizeMs: Double = 25.0,
        hopSizeMs: Double = 10.0,
        preEmphasis: Float = 0.97
    ) {
        self.sampleRate = sampleRate
        self.numMelBins = numMelBins
        self.windowSizeMs = windowSizeMs
        self.hopSizeMs = hopSizeMs
        self.preEmphasis = preEmphasis

        let winSamples = Int(Double(sampleRate) * windowSizeMs / 1000.0)

        // FFT size is next power of 2 >= window size.
        var fft = 1
        while fft < winSamples { fft *= 2 }
        self.fftSize = fft

        // Precompute Hann window.
        var window = [Float](repeating: 0, count: winSamples)
        vDSP_hann_window(&window, vDSP_Length(winSamples), Int32(vDSP_HANN_NORM))
        self.hannWindow = window

        // Precompute mel filter bank.
        self.melFilterBank = Self.computeMelFilterBank(
            numMelBins: numMelBins,
            fftSize: fft,
            sampleRate: sampleRate
        )

        // Create FFT setup once (expensive operation).
        self.log2n = vDSP_Length(log2(Float(fft)))
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Feature Extraction

    /// Extract log-mel spectrogram features from 16-bit PCM audio data.
    ///
    /// - Parameter pcmData: Raw PCM audio data (16kHz, mono, Int16, little-endian).
    /// - Returns: 2D array of shape `[numFrames, numMelBins]` containing log-mel features.
    func extract(from pcmData: Data) -> [[Float]] {
        // Convert Int16 PCM to Float32 samples normalized to [-1, 1].
        let samples = pcmToFloat(pcmData)
        guard samples.count > windowSizeSamples else { return [] }

        // Apply pre-emphasis filter.
        let emphasized = applyPreEmphasis(samples)

        // Compute spectrogram frames.
        let numFrames = max(0, (emphasized.count - windowSizeSamples) / hopSizeSamples + 1)
        guard numFrames > 0 else { return [] }

        var melFrames: [[Float]] = []
        melFrames.reserveCapacity(numFrames)

        for frameIndex in 0..<numFrames {
            let start = frameIndex * hopSizeSamples
            let end = min(start + windowSizeSamples, emphasized.count)
            let frameLength = end - start

            // Extract frame and apply Hann window.
            var frame = [Float](repeating: 0, count: fftSize)
            for i in 0..<frameLength {
                frame[i] = emphasized[start + i] * hannWindow[min(i, hannWindow.count - 1)]
            }

            // Compute power spectrum via FFT.
            let powerSpectrum = computePowerSpectrum(frame)

            // Apply mel filter bank.
            let melEnergies = applyMelFilterBank(powerSpectrum)

            // Apply log with floor to avoid -inf.
            let logMel = melEnergies.map { log(max($0, 1e-10)) }

            melFrames.append(logMel)
        }

        return melFrames
    }

    // MARK: - Private Helpers

    /// Convert Int16 PCM data to normalized Float32 samples.
    private func pcmToFloat(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            // Convert Int16 → Float32, normalizing by Int16.max.
            var scale = Float(Int16.max)
            vDSP_vflt16(int16Ptr, 1, &floatSamples, 1, vDSP_Length(sampleCount))
            vDSP_vsdiv(floatSamples, 1, &scale, &floatSamples, 1, vDSP_Length(sampleCount))
        }

        return floatSamples
    }

    /// Apply pre-emphasis filter: y[n] = x[n] - α * x[n-1].
    private func applyPreEmphasis(_ samples: [Float]) -> [Float] {
        guard samples.count > 1 else { return samples }
        var result = [Float](repeating: 0, count: samples.count)
        result[0] = samples[0]
        for i in 1..<samples.count {
            result[i] = samples[i] - preEmphasis * samples[i - 1]
        }
        return result
    }

    /// Compute the power spectrum of a windowed frame using vDSP FFT.
    private func computePowerSpectrum(_ frame: [Float]) -> [Float] {
        // Pack real data into split complex format.
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        // Convert real input to split complex format for vDSP.
        frame.withUnsafeBufferPointer { framePtr in
            framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
            }
        }

        // Perform FFT using the cached setup.
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // Compute power spectrum (magnitude squared).
        var powerSpectrum = [Float](repeating: 0, count: halfN + 1)

        // DC component.
        powerSpectrum[0] = realPart[0] * realPart[0]

        // Nyquist component (stored in imagPart[0] by vDSP convention).
        powerSpectrum[halfN] = imagPart[0] * imagPart[0]

        // Remaining components.
        for i in 1..<halfN {
            powerSpectrum[i] = realPart[i] * realPart[i] + imagPart[i] * imagPart[i]
        }

        // Normalize by FFT size squared.
        let normFactor = Float(fftSize * fftSize)
        vDSP_vsdiv(powerSpectrum, 1, [normFactor], &powerSpectrum, 1, vDSP_Length(halfN + 1))

        return powerSpectrum
    }

    /// Apply mel filter bank to a power spectrum.
    private func applyMelFilterBank(_ powerSpectrum: [Float]) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: numMelBins)

        for (melBin, filter) in melFilterBank.enumerated() {
            let filterLen = min(filter.count, powerSpectrum.count)
            var energy: Float = 0
            vDSP_dotpr(powerSpectrum, 1, filter, 1, &energy, vDSP_Length(filterLen))
            melEnergies[melBin] = energy
        }

        return melEnergies
    }

    // MARK: - Mel Filter Bank Construction

    /// Convert frequency in Hz to mel scale.
    private static func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    /// Convert mel scale to frequency in Hz.
    private static func melToHz(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    /// Compute triangular mel filter bank weights.
    static func computeMelFilterBank(
        numMelBins: Int,
        fftSize: Int,
        sampleRate: Int
    ) -> [[Float]] {
        let numFFTBins = fftSize / 2 + 1
        let maxFreq = Float(sampleRate) / 2.0

        let melMin = hzToMel(0)
        let melMax = hzToMel(maxFreq)

        // Create evenly spaced mel-scale points.
        let numPoints = numMelBins + 2
        var melPoints = [Float](repeating: 0, count: numPoints)
        let melStep = (melMax - melMin) / Float(numPoints - 1)
        for i in 0..<numPoints {
            melPoints[i] = melMin + Float(i) * melStep
        }

        // Convert back to Hz.
        let hzPoints = melPoints.map { melToHz($0) }

        // Convert Hz to FFT bin indices.
        let binPoints = hzPoints.map { Int(floor($0 * Float(fftSize) / Float(sampleRate))) }

        // Build triangular filters.
        var filterBank: [[Float]] = []
        filterBank.reserveCapacity(numMelBins)

        for m in 0..<numMelBins {
            var filter = [Float](repeating: 0, count: numFFTBins)

            let left = binPoints[m]
            let center = binPoints[m + 1]
            let right = binPoints[m + 2]

            // Rising slope.
            if center > left {
                for k in left...center where k < numFFTBins {
                    filter[k] = Float(k - left) / Float(center - left)
                }
            }

            // Falling slope.
            if right > center {
                for k in center...right where k < numFFTBins {
                    filter[k] = Float(right - k) / Float(right - center)
                }
            }

            filterBank.append(filter)
        }

        return filterBank
    }
}
