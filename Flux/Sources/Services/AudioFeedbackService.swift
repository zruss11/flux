import AppKit
import Foundation

@Observable
@MainActor
final class AudioFeedbackService {
    static let shared = AudioFeedbackService()

    var isSoundEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "dictationSoundsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "dictationSoundsEnabled") }
    }

    enum Sound: String, CaseIterable {
        case dictationStart = "dictation_start"
        case dictationStop = "dictation_stop"
        case dictationSuccess = "dictation_success"
        case error = "dictation_error"
    }

    private var soundCache: [Sound: NSSound] = [:]

    private init() {
        UserDefaults.standard.register(defaults: ["dictationSoundsEnabled": false])
        preloadSounds()
    }

    private func preloadSounds() {
        for sound in Sound.allCases {
            guard let url = Bundle.module.url(
                forResource: sound.rawValue,
                withExtension: "caf"
            ) else {
                Log.audio.warning("Sound file not found: \(sound.rawValue).caf")
                continue
            }

            guard let nsSound = NSSound(contentsOf: url, byReference: false) else {
                Log.audio.warning("Failed to load sound: \(sound.rawValue)")
                continue
            }

            soundCache[sound] = nsSound
        }

        Log.audio.info("Preloaded \(self.soundCache.count)/\(Sound.allCases.count) sounds")
    }

    func play(_ sound: Sound) {
        guard isSoundEnabled else { return }

        guard let template = soundCache[sound] else { return }

        guard let player = template.copy() as? NSSound else { return }
        player.play()
    }
}
