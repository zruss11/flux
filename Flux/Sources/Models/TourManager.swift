import SwiftUI

@MainActor
@Observable
final class TourManager {
    static let shared = TourManager()

    var isActive = false
    var currentStepIndex = 0

    let steps: [TourStep] = [
        TourStep(
            id: 0,
            title: "Welcome to Flux",
            subtitle: "Your AI copilot lives right here in the notch.\nClick or hover to open it anytime.",
            icon: "sparkles",
            iconColor: .white,
            animationStyle: .pulse
        ),
        TourStep(
            id: 1,
            title: "AI Chat",
            subtitle: "Ask anything. Flux can read your screen,\nrun commands, and take actions on your behalf.",
            icon: "bubble.left.and.bubble.right",
            iconColor: .blue,
            animationStyle: .bounce
        ),
        TourStep(
            id: 2,
            title: "Screen Awareness",
            subtitle: "Flux sees what you see. It reads window contents,\nbuttons, and text — not just screenshots.",
            icon: "eye.fill",
            iconColor: .cyan,
            animationStyle: .shimmer
        ),
        TourStep(
            id: 3,
            title: "Voice Dictation",
            subtitle: "Hold ⌘⌥ to dictate anywhere.\nTranscribed locally on-device.",
            icon: "waveform",
            iconColor: .green,
            animationStyle: .wave
        ),
        TourStep(
            id: 4,
            title: "Skills & Tools",
            subtitle: "Install skills to extend Flux.\nType $ in chat to browse and activate them.",
            icon: "puzzlepiece.extension",
            iconColor: .purple,
            animationStyle: .burst
        ),
    ]

    var currentStep: TourStep? {
        guard isActive, steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    var progress: Double {
        Double(currentStepIndex + 1) / Double(steps.count)
    }

    func start() {
        currentStepIndex = 0
        isActive = true
    }

    func next() {
        guard currentStepIndex < steps.count - 1 else {
            complete()
            return
        }
        currentStepIndex += 1
    }

    func previous() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }

    func skip() {
        complete()
    }

    func complete() {
        isActive = false
        currentStepIndex = 0
        UserDefaults.standard.set(true, forKey: "hasCompletedTour")
    }

    private init() {}
}
