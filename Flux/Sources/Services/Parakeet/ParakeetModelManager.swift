import CoreML
import Foundation
import os

// MARK: - ParakeetModelManager

/// Manages downloading, caching, and loading of Parakeet TDT v3 CoreML models
/// from HuggingFace.
///
/// Models are downloaded on first use from the FluidInference HuggingFace repository
/// and cached locally in the application support directory. Once loaded, compiled
/// CoreML models are held in memory for fast inference.
@Observable
@MainActor
final class ParakeetModelManager {

    static let shared = ParakeetModelManager()

    // MARK: - Public State

    /// Whether all required models are loaded and ready for inference.
    private(set) var isReady = false

    /// Progress of model download (0.0–1.0), or `nil` if not downloading.
    private(set) var downloadProgress: Double?

    /// Human-readable status message for UI display.
    private(set) var statusMessage = "Models not loaded"

    /// Whether a download or load operation is in progress.
    private(set) var isLoading = false

    // MARK: - Model Source

    /// HuggingFace repository for Parakeet TDT v3 CoreML models.
    static let huggingFaceRepo = "FluidInference/parakeet-tdt-0.6b-v3-coreml"

    /// Base URL for downloading individual files from HuggingFace.
    static let huggingFaceBaseURL = URL(
        string: "https://huggingface.co/\(huggingFaceRepo)/resolve/main/"
    )!

    /// The local directory name under Application Support for cached models.
    static let modelVariant = "parakeet-tdt-0.6b-v3-coreml"

    /// Required CoreML model directories and their constituent files.
    /// Each `.mlmodelc` directory contains several files that must all be downloaded.
    enum ModelFile: String, CaseIterable, Sendable {
        case encoder = "Encoder"
        case decoder = "Decoder"
        case jointDecision = "JointDecision"
        case preprocessor = "Preprocessor"
        case melEncoder = "MelEncoder"

        var directoryName: String { rawValue + ".mlmodelc" }

        /// The files inside each `.mlmodelc` directory on HuggingFace.
        var subFiles: [String] {
            switch self {
            case .decoder:
                // ParakeetDecoder has no metadata.json in some repos
                return ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin", "analytics/coremldata.bin"]
            default:
                return ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin", "analytics/coremldata.bin"]
            }
        }

        /// Critical files that must be present for the model to load successfully.
        var requiredSubFiles: [String] {
            ["coremldata.bin", "weights/weight.bin"]
        }
    }

    /// Vocabulary files to download.
    static let vocabFiles = ["parakeet_v3_vocab.json", "parakeet_vocab.json"]

    // MARK: - Loaded Models

    private(set) var encoderModel: MLModel?
    private(set) var decoderModel: MLModel?
    private(set) var jointDecisionModel: MLModel?
    private(set) var preprocessorModel: MLModel?
    private(set) var melEncoderModel: MLModel?

    /// Token vocabulary loaded from `parakeet_v3_vocab.json`.
    private(set) var vocabulary: [Int: String] = [:]

    // MARK: - Private

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Flux", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelVariant, isDirectory: true)
    }

    private init() {}

    // MARK: - Public API

    /// Preload models if they are already cached on disk. Call during app startup.
    func preloadIfNeeded() {
        guard !isReady, !isLoading else { return }
        guard areModelsCached else {
            statusMessage = "Models not downloaded"
            Log.voice.info("[ParakeetModelManager] Models not found on disk")
            return
        }

        Task {
            await loadModelsFromDisk()
        }
    }

    /// Load all models from disk into memory.
    func loadModelsFromDisk() async {
        guard !isReady, !isLoading else { return }
        isLoading = true
        statusMessage = "Loading models…"

        let modelsDir = Self.modelsDirectory

        do {
            // Load vocabulary — prefer v3, fall back to standard.
            let v3VocabURL = modelsDir.appendingPathComponent("parakeet_v3_vocab.json")
            let stdVocabURL = modelsDir.appendingPathComponent("parakeet_vocab.json")

            if FileManager.default.fileExists(atPath: v3VocabURL.path) {
                vocabulary = try loadVocabulary(from: v3VocabURL)
            } else if FileManager.default.fileExists(atPath: stdVocabURL.path) {
                vocabulary = try loadVocabulary(from: stdVocabURL)
            } else {
                throw NSError(domain: "ParakeetModelManager", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "No vocabulary file found"])
            }

            // Configure compute units — prefer ANE + GPU for best performance.
            let config = MLModelConfiguration()
            config.computeUnits = .all

            // Load each CoreML model.
            encoderModel = try await MLModel.load(
                contentsOf: modelsDir.appendingPathComponent(ModelFile.encoder.directoryName),
                configuration: config
            )
            decoderModel = try await MLModel.load(
                contentsOf: modelsDir.appendingPathComponent(ModelFile.decoder.directoryName),
                configuration: config
            )
            jointDecisionModel = try await MLModel.load(
                contentsOf: modelsDir.appendingPathComponent(ModelFile.jointDecision.directoryName),
                configuration: config
            )
            preprocessorModel = try await MLModel.load(
                contentsOf: modelsDir.appendingPathComponent(ModelFile.preprocessor.directoryName),
                configuration: config
            )
            melEncoderModel = try await MLModel.load(
                contentsOf: modelsDir.appendingPathComponent(ModelFile.melEncoder.directoryName),
                configuration: config
            )

            isReady = true
            statusMessage = "Models loaded"
            Log.voice.info("[ParakeetModelManager] All models loaded successfully")
        } catch {
            Log.voice.error("[ParakeetModelManager] Failed to load models: \(error.localizedDescription)")
            statusMessage = "Failed to load: \(error.localizedDescription)"
            unloadModels()
        }

        isLoading = false
    }

    /// Download models from HuggingFace and then load them.
    func downloadAndLoadModels() async {
        guard !isLoading else { return }
        isLoading = true
        downloadProgress = 0.0
        statusMessage = "Downloading models…"

        let modelsDir = Self.modelsDirectory

        do {
            // Collect all files to download.
            var allDownloads: [(remotePath: String, localPath: URL)] = []

            for modelFile in ModelFile.allCases {
                let modelDir = modelsDir.appendingPathComponent(modelFile.directoryName)
                try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

                // Create weights subdirectory.
                let weightsDir = modelDir.appendingPathComponent("weights")
                try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)

                // Create analytics subdirectory.
                let analyticsDir = modelDir.appendingPathComponent("analytics")
                try FileManager.default.createDirectory(at: analyticsDir, withIntermediateDirectories: true)

                for subFile in modelFile.subFiles {
                    let remotePath = "\(modelFile.directoryName)/\(subFile)"
                    let localPath = modelDir.appendingPathComponent(subFile)
                    allDownloads.append((remotePath, localPath))
                }
            }

            // Add vocabulary files.
            for vocabFile in Self.vocabFiles {
                allDownloads.append((vocabFile, modelsDir.appendingPathComponent(vocabFile)))
            }

            let totalFiles = Double(allDownloads.count)
            var completedFiles = 0.0
            var failedFiles: [String] = []

            for (remotePath, localPath) in allDownloads {
                if FileManager.default.fileExists(atPath: localPath.path) {
                    completedFiles += 1
                    downloadProgress = completedFiles / totalFiles
                    continue
                }

                let remoteURL = Self.huggingFaceBaseURL.appendingPathComponent(remotePath)

                do {
                    let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)

                    // Check for HTTP errors (404, etc.)
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode != 200 {
                        Log.voice.warning("[ParakeetModelManager] HTTP \(httpResponse.statusCode) for \(remotePath), skipping")
                        failedFiles.append(remotePath)
                        // Do NOT increment progress for failed downloads.
                        continue
                    }

                    try FileManager.default.moveItem(at: tempURL, to: localPath)
                    Log.voice.info("[ParakeetModelManager] Downloaded \(remotePath)")
                } catch {
                    Log.voice.warning("[ParakeetModelManager] Failed to download \(remotePath): \(error.localizedDescription)")
                    failedFiles.append(remotePath)
                    // Do NOT increment progress for failed downloads.
                    continue
                }

                completedFiles += 1
                downloadProgress = completedFiles / totalFiles
            }

            // Surface download failures before attempting to load.
            if !failedFiles.isEmpty {
                let failedList = failedFiles.joined(separator: ", ")
                Log.voice.error("[ParakeetModelManager] Failed to download \(failedFiles.count) file(s): \(failedList)")
                statusMessage = "Download incomplete: \(failedFiles.count) file(s) failed"
                isLoading = false
                downloadProgress = nil
                return
            }

            downloadProgress = nil
            statusMessage = "Download complete, loading…"

        } catch {
            Log.voice.error("[ParakeetModelManager] Download setup failed: \(error.localizedDescription)")
            statusMessage = "Download failed: \(error.localizedDescription)"
            isLoading = false
            downloadProgress = nil
            return
        }

        isLoading = false
        await loadModelsFromDisk()
    }

    /// Unload all models from memory.
    func unloadModels() {
        encoderModel = nil
        decoderModel = nil
        jointDecisionModel = nil
        preprocessorModel = nil
        melEncoderModel = nil
        vocabulary = [:]
        isReady = false
        statusMessage = "Models not loaded"
    }

    /// Delete cached model files from disk.
    func deleteCachedModels() {
        unloadModels()
        let modelsDir = Self.modelsDirectory
        try? FileManager.default.removeItem(at: modelsDir)
        statusMessage = "Models deleted"
        Log.voice.info("[ParakeetModelManager] Cached models deleted")
    }

    /// Whether model files exist on disk (even if not loaded into memory).
    ///
    /// This validates that each model directory exists AND contains critical
    /// subfiles (e.g., `coremldata.bin`). A partial download will not pass.
    var areModelsCached: Bool {
        let modelsDir = Self.modelsDirectory
        return ModelFile.allCases.allSatisfy { file in
            let modelDir = modelsDir.appendingPathComponent(file.directoryName)
            // Check that the directory exists AND all required subfiles are present.
            return file.requiredSubFiles.allSatisfy { subFile in
                FileManager.default.fileExists(
                    atPath: modelDir.appendingPathComponent(subFile).path
                )
            }
        }
    }

    /// Estimated size of cached models on disk, in bytes.
    var cachedModelSize: Int64 {
        let modelsDir = Self.modelsDirectory
        guard FileManager.default.fileExists(atPath: modelsDir.path) else { return 0 }
        let enumerator = FileManager.default.enumerator(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Private

    private func loadVocabulary(from url: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: Int].self, from: data)
        // Invert: vocab.json maps token_string → token_id,
        // but for decoding we need token_id → token_string.
        var vocab: [Int: String] = [:]
        for (token, id) in decoded {
            vocab[id] = token
        }
        return vocab
    }
}
