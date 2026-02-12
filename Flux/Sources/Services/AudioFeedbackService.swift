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
    private let resourceBundles: [Bundle]

    private init() {
        UserDefaults.standard.register(defaults: ["dictationSoundsEnabled": false])
        resourceBundles = Self.discoverResourceBundles()
        preloadSounds()
    }

    private func preloadSounds() {
        for sound in Sound.allCases {
            guard let url = resolveSoundURL(named: sound.rawValue) else {
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

    private static func discoverResourceBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main]

        if let resourceURL = Bundle.main.resourceURL {
            for bundleName in ["Flux_Flux.bundle", "Flux.bundle"] {
                let bundleURL = resourceURL.appendingPathComponent(bundleName)
                if let bundle = Bundle(url: bundleURL) {
                    bundles.append(bundle)
                }
            }
        }

        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)

        var seen = Set<String>()
        return bundles.filter { bundle in
            let key = bundle.bundleURL.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }

    private func resolveSoundURL(named soundName: String) -> URL? {
        for bundle in resourceBundles {
            if let url = bundle.url(forResource: soundName, withExtension: "caf", subdirectory: "Sounds") {
                return url
            }
            if let url = bundle.url(forResource: soundName, withExtension: "caf") {
                return url
            }
        }
        return nil
    }

    func play(_ sound: Sound) {
        guard isSoundEnabled else { return }

        guard let template = soundCache[sound] else { return }

        guard let player = template.copy() as? NSSound else { return }
        player.play()
    }
}
