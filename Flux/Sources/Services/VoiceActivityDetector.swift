import Foundation

/// Monitors an `AudioLevelMeter` for sustained silence and fires a callback
/// when the RMS level stays below a threshold for a configurable duration.
@MainActor
final class VoiceActivityDetector {

    private var pollTimer: Timer?
    private var silenceStart: Date?
    private var onSilence: (() -> Void)?

    private var meter: AudioLevelMeter?
    private var silenceThreshold: Float = 0.01
    private var silenceDuration: TimeInterval = 1.5

    func startMonitoring(
        meter: AudioLevelMeter,
        silenceThreshold: Float = 0.01,
        silenceDuration: TimeInterval = 1.5,
        onSilence: @escaping () -> Void
    ) {
        stopMonitoring()

        self.meter = meter
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.onSilence = onSilence
        self.silenceStart = nil

        // Poll at ~30 Hz.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        silenceStart = nil
        onSilence = nil
        meter = nil
    }

    private func poll() {
        guard let meter else { return }
        let rms = meter.currentLevels().rms

        if rms < silenceThreshold {
            if silenceStart == nil {
                silenceStart = Date()
            } else if Date().timeIntervalSince(silenceStart!) >= silenceDuration {
                let callback = onSilence
                stopMonitoring()
                callback?()
            }
        } else {
            // Speech detected — reset the silence window.
            silenceStart = nil
        }
    }
}
