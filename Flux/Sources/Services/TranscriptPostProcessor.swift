import Foundation

/// Unified voice transcript post-processing pipeline inspired by Almond's
/// multi-stage ASR processor.
///
/// Stages run in order:
/// 1. Filler removal (`FillerWordCleaner`)
/// 2. Fragment repair (`FragmentRepairProcessor`)
/// 3. Intent correction (`IntentCorrectionProcessor`)
/// 4. Number conversion (`NumberConversionProcessor`)
/// 5. Dictionary corrections (`DictionaryCorrector`)
///
/// Each stage is individually toggleable via `UserDefaults` flags.
struct TranscriptPostProcessor {

    // MARK: - UserDefaults Keys

    /// Master switch — when `false`, returns the raw text unmodified.
    static let enabledKey = "transcriptPostProcessingEnabled"

    static let fillerRemovalKey = "dictationAutoCleanFillers"
    static let fragmentRepairKey = "dictationFragmentRepair"
    static let intentCorrectionKey = "dictationIntentCorrection"
    static let numberConversionKey = "dictationNumberConversion"
    static let dictionaryCorrectionKey = "dictationDictionaryCorrection"

    // MARK: - Defaults Registration

    /// Call once at app launch to ensure all toggle defaults are set.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabledKey: true,
            fillerRemovalKey: true,
            fragmentRepairKey: true,
            intentCorrectionKey: true,
            numberConversionKey: true,
            dictionaryCorrectionKey: true,
        ])
    }

    // MARK: - Pipeline

    /// Runs the full post-processing pipeline on a raw transcript.
    @MainActor
    static func process(_ text: String) -> String {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        var result = text

        // Stage 1: Filler removal
        if UserDefaults.standard.bool(forKey: fillerRemovalKey) {
            result = FillerWordCleaner.clean(result)
        }

        // Stage 2: Fragment repair
        if UserDefaults.standard.bool(forKey: fragmentRepairKey) {
            result = FragmentRepairProcessor.process(result)
        }

        // Stage 3: Intent correction
        if UserDefaults.standard.bool(forKey: intentCorrectionKey) {
            result = IntentCorrectionProcessor.process(result)
        }

        // Stage 4: Number conversion
        if UserDefaults.standard.bool(forKey: numberConversionKey) {
            result = NumberConversionProcessor.process(result)
        }

        // Stage 5: Dictionary corrections
        if UserDefaults.standard.bool(forKey: dictionaryCorrectionKey) {
            result = DictionaryCorrector.apply(result, using: CustomDictionaryStore.shared.entries)
        }

        return result
    }
}
