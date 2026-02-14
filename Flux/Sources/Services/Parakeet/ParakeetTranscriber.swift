import CoreML
import Foundation
import os

// MARK: - ParakeetTranscriber

/// CoreML-based RNNT/TDT transcriber using Parakeet TDT 0.6B models.
///
/// Pipeline:
/// ```
/// PCM Audio → FBank Features → Preprocessor → Encoder → Decoder + Joint → Token IDs → Text
/// ```
///
/// This transcriber operates in batch mode: it processes a complete audio recording
/// after capture is finished. Streaming (partial) transcription is planned for a future phase.
actor ParakeetTranscriber {

    // MARK: - Error Types

    enum TranscriptionError: LocalizedError {
        case modelsNotLoaded
        case featureExtractionFailed
        case encoderFailed(String)
        case decoderFailed(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .modelsNotLoaded:
                return "Parakeet models are not loaded."
            case .featureExtractionFailed:
                return "Failed to extract audio features."
            case .encoderFailed(let detail):
                return "Parakeet encoder failed: \(detail)"
            case .decoderFailed(let detail):
                return "Parakeet decoder failed: \(detail)"
            case .emptyAudio:
                return "No audio data to transcribe."
            }
        }
    }

    // MARK: - Properties

    private let featureExtractor = FBankFeatureExtractor()
    private let maxDecodingSteps = 1000

    // MARK: - Transcription

    /// Transcribe PCM audio data to text using Parakeet TDT models.
    ///
    /// - Parameters:
    ///   - pcmData: Raw PCM audio (16kHz, mono, Int16, little-endian).
    ///   - modelManager: The model manager holding loaded CoreML models.
    /// - Returns: The transcribed text.
    @MainActor
    func transcribe(pcmData: Data, modelManager: ParakeetModelManager) async throws -> String {
        guard modelManager.isReady else {
            throw TranscriptionError.modelsNotLoaded
        }

        guard !pcmData.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Extract mel-scale features.
        let melFeatures = featureExtractor.extract(from: pcmData)
        guard !melFeatures.isEmpty else {
            throw TranscriptionError.featureExtractionFailed
        }

        let featureTime = CFAbsoluteTimeGetCurrent()
        Log.voice.info("[ParakeetTranscriber] Feature extraction: \(melFeatures.count) frames in \(String(format: "%.1f", (featureTime - startTime) * 1000))ms")

        // Step 2: Run encoder on mel features.
        let encoderOutput = try await runEncoder(
            melFeatures: melFeatures,
            encoderModel: modelManager.encoderModel!,
            preprocessorModel: modelManager.preprocessorModel
        )

        let encodeTime = CFAbsoluteTimeGetCurrent()
        Log.voice.info("[ParakeetTranscriber] Encoding: \(String(format: "%.1f", (encodeTime - featureTime) * 1000))ms")

        // Step 3: Run greedy RNNT/TDT decoding.
        let tokenIds = try greedyDecode(
            encoderOutput: encoderOutput,
            decoderModel: modelManager.decoderModel!,
            jointModel: modelManager.jointDecisionModel!
        )

        let decodeTime = CFAbsoluteTimeGetCurrent()
        Log.voice.info("[ParakeetTranscriber] Decoding: \(tokenIds.count) tokens in \(String(format: "%.1f", (decodeTime - encodeTime) * 1000))ms")

        // Step 4: Convert tokens to text.
        let tokenizer = ParakeetTokenizer(vocabulary: modelManager.vocabulary)
        let text = tokenizer.decodeRNNT(tokenIds)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let audioDuration = Double(pcmData.count) / Double(MemoryLayout<Int16>.size) / 16000.0
        let realtimeFactor = totalTime / max(audioDuration, 0.001)

        Log.voice.info("[ParakeetTranscriber] Total: \(String(format: "%.1f", totalTime * 1000))ms, RTF: \(String(format: "%.2f", realtimeFactor))")

        return text
    }

    // MARK: - Encoder

    /// Run the Parakeet encoder on mel spectrogram features.
    ///
    /// Pipeline: mel features → (optional Preprocessor) → Streaming Encoder → encoder output
    private func runEncoder(
        melFeatures: [[Float]],
        encoderModel: MLModel,
        preprocessorModel: MLModel?
    ) async throws -> MLMultiArray {
        let numFrames = melFeatures.count
        let numMelBins = melFeatures.first?.count ?? 80

        // Create input MLMultiArray: [1, numFrames, numMelBins]
        let inputArray = try MLMultiArray(
            shape: [1, NSNumber(value: numFrames), NSNumber(value: numMelBins)],
            dataType: .float32
        )

        // Fill the input array.
        for frame in 0..<numFrames {
            for bin in 0..<numMelBins {
                let index = frame * numMelBins + bin
                inputArray[index] = NSNumber(value: melFeatures[frame][bin])
            }
        }

        // Run through preprocessor if available.
        var encoderInput = inputArray
        if let preprocessor = preprocessorModel {
            let preprocInput = try MLDictionaryFeatureProvider(
                dictionary: ["audio_signal" as NSString: inputArray]
            )
            let preprocOutput = try preprocessor.prediction(from: preprocInput)

            if let processed = preprocOutput.featureValue(for: "processed_signal")?.multiArrayValue {
                encoderInput = processed
            }
        }

        // Run encoder.
        let encInput = try MLDictionaryFeatureProvider(
            dictionary: ["audio_features" as NSString: encoderInput]
        )
        let encOutput = try encoderModel.prediction(from: encInput)

        // Extract encoder output. Common output names: "encoder_output", "output", "encoded".
        for name in ["encoder_output", "output", "encoded", "hidden_states"] {
            if let output = encOutput.featureValue(for: name)?.multiArrayValue {
                return output
            }
        }

        // If no known name, try the first available feature.
        let featureNames = encOutput.featureNames
        for name in featureNames {
            if let output = encOutput.featureValue(for: name)?.multiArrayValue {
                return output
            }
        }

        throw TranscriptionError.encoderFailed("No encoder output found")
    }

    // MARK: - Greedy RNNT/TDT Decoder

    /// Perform greedy RNNT/TDT decoding using the decoder and joint network.
    ///
    /// The RNNT decoder processes encoder outputs frame by frame, predicting one token
    /// at a time using the joint network (which combines encoder and decoder states).
    private func greedyDecode(
        encoderOutput: MLMultiArray,
        decoderModel: MLModel,
        jointModel: MLModel
    ) throws -> [Int] {
        var outputTokens: [Int] = []

        // Determine encoder output dimensions.
        let shape = encoderOutput.shape.map(\.intValue)
        let numTimeSteps = shape.count >= 2 ? shape[1] : shape[0]
        let encoderDim = shape.count >= 3 ? shape[2] : (shape.count >= 2 ? shape[1] : shape[0])

        // Initialize decoder hidden state (zeros).
        // The initial token input is typically a blank/start token (ID 0).
        var lastToken = 0

        for t in 0..<numTimeSteps {
            var emitsRemaining = 10 // Max emissions per time step (prevents infinite loops).

            while emitsRemaining > 0 {
                emitsRemaining -= 1

                // Get decoder prediction for the last emitted token.
                let decoderInput = try createDecoderInput(tokenId: lastToken)
                let decoderOutput = try decoderModel.prediction(from: decoderInput)

                guard let decoderHidden = extractFirstMultiArray(from: decoderOutput) else {
                    throw TranscriptionError.decoderFailed("No decoder output")
                }

                // Extract encoder frame at time step t.
                let encoderFrame = try extractEncoderFrame(
                    encoderOutput: encoderOutput,
                    timeStep: t,
                    dim: encoderDim
                )

                // Run joint network.
                let jointInput = try MLDictionaryFeatureProvider(
                    dictionary: [
                        "encoder_output" as NSString: encoderFrame,
                        "decoder_output" as NSString: decoderHidden
                    ]
                )
                let jointOutput = try jointModel.prediction(from: jointInput)

                guard let logits = extractFirstMultiArray(from: jointOutput) else {
                    throw TranscriptionError.decoderFailed("No joint output")
                }

                // Find the token with the highest logit (greedy).
                let predictedToken = argmax(logits)

                // Blank token (0) means "advance to next time step".
                if predictedToken == 0 {
                    break
                }

                // Emit the token.
                outputTokens.append(predictedToken)
                lastToken = predictedToken

                if outputTokens.count >= maxDecodingSteps {
                    break
                }
            }

            if outputTokens.count >= maxDecodingSteps {
                break
            }
        }

        return outputTokens
    }

    // MARK: - Helpers

    /// Create decoder input from a single token ID.
    private func createDecoderInput(tokenId: Int) throws -> MLDictionaryFeatureProvider {
        let tokenArray = try MLMultiArray(shape: [1, 1], dataType: .int32)
        tokenArray[0] = NSNumber(value: Int32(tokenId))
        return try MLDictionaryFeatureProvider(
            dictionary: ["input_ids" as NSString: tokenArray]
        )
    }

    /// Extract a single time step from the encoder output.
    private func extractEncoderFrame(
        encoderOutput: MLMultiArray,
        timeStep: Int,
        dim: Int
    ) throws -> MLMultiArray {
        let frame = try MLMultiArray(shape: [1, 1, NSNumber(value: dim)], dataType: .float32)
        let offset = timeStep * dim
        for i in 0..<dim {
            frame[i] = encoderOutput[offset + i]
        }
        return frame
    }

    /// Extract the first MLMultiArray value from a feature provider.
    private func extractFirstMultiArray(from provider: MLFeatureProvider) -> MLMultiArray? {
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue {
                return array
            }
        }
        return nil
    }

    /// Find the index of the maximum value in an MLMultiArray.
    private func argmax(_ array: MLMultiArray) -> Int {
        let count = array.count
        guard count > 0 else { return 0 }

        var maxIndex = 0
        var maxValue = array[0].floatValue

        for i in 1..<count {
            let value = array[i].floatValue
            if value > maxValue {
                maxValue = value
                maxIndex = i
            }
        }

        return maxIndex
    }
}
