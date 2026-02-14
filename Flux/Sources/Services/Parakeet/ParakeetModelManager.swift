import CoreML
import Foundation
import os

// MARK: - ParakeetModelManager

/// Manages downloading, caching, and loading of Parakeet TDT CoreML models.
///
/// Models are downloaded on first use and cached locally in the application support
/// directory. Once loaded, compiled CoreML models are held in memory for fast inference.
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

    // MARK: - Model Specs

    /// The model variant to use.
    static let modelVariant = "parakeet-tdt-0.6b-v2-coreml"

    /// Required CoreML model files for the Parakeet TDT pipeline.
    enum ModelFile: String, CaseIterable, Sendable {
        case encoder = "streaming_encoder"
        case decoder = "Decoder"
        case jointDecision = "JointDecision"
        case fbank = "FBank"
        case preprocessor = "Preprocessor"

        var filename: String { rawValue + ".mlmodelc" }
    }

    // MARK: - Loaded Models

    private(set) var encoderModel: MLModel?
    private(set) var decoderModel: MLModel?
    private(set) var jointDecisionModel: MLModel?
    private(set) var fbankModel: MLModel?
    private(set) var preprocessorModel: MLModel?

    /// Token vocabulary loaded from `vocab.json`.
    private(set) var vocabulary: [Int: String] = [:]

    // MARK: - Private

    private var isLoading = false

    private static var modelsDirectory: URL {
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

        let modelsDir = Self.modelsDirectory
        let allPresent = ModelFile.allCases.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: modelsDir.appendingPathComponent(file.filename).path
            )
        }

        let vocabPresent = FileManager.default.fileExists(
            atPath: modelsDir.appendingPathComponent("vocab.json").path
        )

        guard allPresent && vocabPresent else {
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
            // Load vocabulary
            let vocabURL = modelsDir.appendingPathComponent("vocab.json")
            vocabulary = try loadVocabulary(from: vocabURL)

            // Configure compute units — prefer ANE + GPU for best performance.
            let config = MLModelConfiguration()
            config.computeUnits = .all

            // Load each CoreML model
            let encoderURL = modelsDir.appendingPathComponent(ModelFile.encoder.filename)
            encoderModel = try await MLModel.load(contentsOf: encoderURL, configuration: config)

            let decoderURL = modelsDir.appendingPathComponent(ModelFile.decoder.filename)
            decoderModel = try await MLModel.load(contentsOf: decoderURL, configuration: config)

            let jointURL = modelsDir.appendingPathComponent(ModelFile.jointDecision.filename)
            jointDecisionModel = try await MLModel.load(contentsOf: jointURL, configuration: config)

            let fbankURL = modelsDir.appendingPathComponent(ModelFile.fbank.filename)
            fbankModel = try await MLModel.load(contentsOf: fbankURL, configuration: config)

            let preprocURL = modelsDir.appendingPathComponent(ModelFile.preprocessor.filename)
            preprocessorModel = try await MLModel.load(contentsOf: preprocURL, configuration: config)

            isReady = true
            statusMessage = "Models loaded"
            Log.voice.info("[ParakeetModelManager] All models loaded successfully")
        } catch {
            Log.voice.error("[ParakeetModelManager] Failed to load models: \(error.localizedDescription)")
            statusMessage = "Failed to load models"
            unloadModels()
        }

        isLoading = false
    }

    /// Download models from the configured URL.
    ///
    /// - Parameter baseURL: The base URL where model files are hosted.
    func downloadModels(from baseURL: URL) async throws {
        guard !isLoading else { return }
        isLoading = true
        downloadProgress = 0.0
        statusMessage = "Downloading models…"

        let modelsDir = Self.modelsDirectory

        // Create the models directory if needed.
        try FileManager.default.createDirectory(
            at: modelsDir,
            withIntermediateDirectories: true
        )

        let allFiles = ModelFile.allCases.map(\.filename) + ["vocab.json"]
        let totalFiles = Double(allFiles.count)

        for (index, filename) in allFiles.enumerated() {
            let remoteURL = baseURL.appendingPathComponent(filename)
            let localURL = modelsDir.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: localURL.path) {
                Log.voice.info("[ParakeetModelManager] \(filename) already cached")
            } else {
                let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
                try FileManager.default.moveItem(at: tempURL, to: localURL)
                Log.voice.info("[ParakeetModelManager] Downloaded \(filename)")
            }

            downloadProgress = Double(index + 1) / totalFiles
        }

        downloadProgress = nil
        statusMessage = "Download complete"
        isLoading = false

        await loadModelsFromDisk()
    }

    /// Unload all models from memory.
    func unloadModels() {
        encoderModel = nil
        decoderModel = nil
        jointDecisionModel = nil
        fbankModel = nil
        preprocessorModel = nil
        vocabulary = [:]
        isReady = false
        statusMessage = "Models not loaded"
    }

    /// Whether model files exist on disk (even if not loaded into memory).
    var areModelsCached: Bool {
        let modelsDir = Self.modelsDirectory
        return ModelFile.allCases.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: modelsDir.appendingPathComponent(file.filename).path
            )
        }
    }

    // MARK: - Private

    private func loadVocabulary(from url: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: Int].self, from: data)
        // Invert: the vocab.json maps token_string → token_id,
        // but for decoding we need token_id → token_string.
        var vocab: [Int: String] = [:]
        for (token, id) in decoded {
            vocab[id] = token
        }
        return vocab
    }
}
