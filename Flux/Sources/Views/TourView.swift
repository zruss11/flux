import SwiftUI

struct TourView: View {
    var onComplete: () -> Void

    @State private var tourManager = TourManager.shared
    @State private var appeared = false
    @State private var stepId = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Skip button
            HStack {
                Spacer()
                if !tourManager.isLastStep {
                    Button {
                        tourManager.skip()
                        onComplete()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 28)
            .padding(.horizontal, 8)

            Spacer()

            // Step content
            TourStepContent(
                step: tourManager.currentStep ?? tourManager.steps[0],
                appeared: appeared,
                reduceMotion: reduceMotion
            )
            .id(stepId)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<tourManager.steps.count, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i == tourManager.currentStepIndex ? 0.9 : 0.2))
                        .frame(
                            width: i == tourManager.currentStepIndex ? 8 : 6,
                            height: i == tourManager.currentStepIndex ? 8 : 6
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tourManager.currentStepIndex)
                }
            }
            .padding(.bottom, 16)

            // Navigation buttons
            HStack(spacing: 12) {
                if tourManager.currentStepIndex > 0 {
                    Button {
                        advanceStep(forward: false)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                            Text("Back")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    if tourManager.isLastStep {
                        tourManager.complete()
                        onComplete()
                    } else {
                        advanceStep(forward: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tourManager.isLastStep ? "Get Started" : "Next")
                            .font(.system(size: 13, weight: .semibold))
                        if !tourManager.isLastStep {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(tourManager.isLastStep ? .black : .white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(tourManager.isLastStep ? .white : .white.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .opacity(appeared ? 1 : 0)
            .animation(
                reduceMotion ? .easeIn(duration: 0.1) : .easeInOut(duration: 0.3).delay(0.5),
                value: appeared
            )
        }
        .onAppear {
            appeared = true
        }
    }

    private func advanceStep(forward: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85)) {
            appeared = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.15 : 0.25)) {
            if forward {
                tourManager.next()
            } else {
                tourManager.previous()
            }
            stepId = UUID()

            withAnimation(reduceMotion ? .easeIn(duration: 0.1) : .spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Step Content

private struct TourStepContent: View {
    let step: TourStep
    let appeared: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            TourIconView(step: step, reduceMotion: reduceMotion)
                .frame(height: 120)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .easeIn(duration: 0.1) : .spring(response: 0.6, dampingFraction: 0.65).delay(0.1),
                    value: appeared
                )

            // Title
            Text(step.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .easeIn(duration: 0.1) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.25),
                    value: appeared
                )

            // Subtitle
            Text(step.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .offset(y: appeared ? 0 : 15)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion ? .easeIn(duration: 0.1) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.35),
                    value: appeared
                )

            // Keyboard shortcut badge for voice step
            if step.animationStyle == .wave {
                KeyboardShortcutBadge()
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeIn(duration: 0.1) : .easeInOut(duration: 0.3).delay(0.45),
                        value: appeared
                    )
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Tour Icon View

private struct TourIconView: View {
    let step: TourStep
    let reduceMotion: Bool

    @State private var animating = false

    var body: some View {
        ZStack {
            switch step.animationStyle {
            case .pulse:
                pulseIcon
            case .bounce:
                bounceIcon
            case .shimmer:
                shimmerIcon
            case .wave:
                waveIcon
            case .burst:
                burstIcon
            }
        }
        .onAppear {
            if !reduceMotion {
                animating = true
            }
        }
        .onDisappear {
            animating = false
        }
    }

    // MARK: Pulse (Welcome)

    private var pulseIcon: some View {
        ZStack {
            // Glow ring
            Circle()
                .fill(.white.opacity(animating ? 0.08 : 0.02))
                .frame(width: 100, height: 100)
                .scaleEffect(animating ? 1.1 : 0.9)

            Image(systemName: step.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(step.iconColor)
                .scaleEffect(animating ? 1.08 : 0.92)
                .shadow(color: .white.opacity(animating ? 0.6 : 0.1), radius: animating ? 12 : 4)
        }
        .animation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: animating
        )
    }

    // MARK: Bounce (AI Chat)

    private var bounceIcon: some View {
        Image(systemName: step.icon)
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(step.iconColor)
            .offset(y: animating ? -6 : 6)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: animating
            )
    }

    // MARK: Shimmer (Screen Awareness)

    private var shimmerIcon: some View {
        ZStack {
            Image(systemName: step.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(step.iconColor)
                .shadow(color: step.iconColor.opacity(animating ? 0.5 : 0.1), radius: animating ? 10 : 3)

            // Orbiting spark dots
            TourSparkDot(animating: animating, offset: CGPoint(x: 20, y: -18), delay: 0)
            TourSparkDot(animating: animating, offset: CGPoint(x: -16, y: -22), delay: 0.3)
            TourSparkDot(animating: animating, offset: CGPoint(x: 22, y: 14), delay: 0.6)
            TourSparkDot(animating: animating, offset: CGPoint(x: -20, y: 16), delay: 0.9)
        }
        .animation(
            .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
            value: animating
        )
    }

    // MARK: Wave (Voice Dictation)

    private var waveIcon: some View {
        VStack(spacing: 16) {
            Image(systemName: step.icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(step.iconColor)

            TourWaveformBars(animating: animating)
        }
    }

    // MARK: Burst (Skills - final step)

    private var burstIcon: some View {
        ZStack {
            // Celebration particles
            if animating {
                TourCelebrationParticles()
            }

            Image(systemName: step.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(step.iconColor)
                .scaleEffect(animating ? 1.05 : 0.95)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: animating
                )
        }
    }
}

// MARK: - Spark Dot

private struct TourSparkDot: View {
    let animating: Bool
    let offset: CGPoint
    let delay: Double

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 3, height: 3)
            .opacity(animating ? 0.9 : 0.1)
            .scaleEffect(animating ? 1.3 : 0.4)
            .offset(x: offset.x, y: offset.y)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(delay),
                value: animating
            )
    }
}

// MARK: - Waveform Bars

private struct TourWaveformBars: View {
    let animating: Bool

    private let barCount = 8
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = animating ? timeline.date.timeIntervalSinceReferenceDate : 0

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let phase = Double(index) * 0.9
                    let wave = sin(time * 2.5 + phase) * 0.4
                        + sin(time * 4.5 + phase * 1.5) * 0.35
                        + sin(time * 7.0 + phase * 0.8) * 0.25
                    let normalized = Float((wave + 1.0) / 2.0 * 0.85 + 0.15)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(.green.opacity(0.8))
                        .frame(width: barWidth, height: barHeight(for: normalized))
                }
            }
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let maxH: CGFloat = 28
        let minH: CGFloat = 4
        return minH + CGFloat(level) * (maxH - minH)
    }
}

// MARK: - Keyboard Shortcut Badge

private struct KeyboardShortcutBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            KeyCap(label: "⌘")
            Text("+")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            KeyCap(label: "⌥")
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - Celebration Particles

private struct TourCelebrationParticles: View {
    @State private var particles: [CelebrationParticle] = (0..<24).map { _ in
        CelebrationParticle()
    }
    @State private var burst = false

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: burst ? particle.endOffset.x : 0,
                        y: burst ? particle.endOffset.y : 0
                    )
                    .opacity(burst ? 0 : particle.opacity)
                    .scaleEffect(burst ? 0.3 : 1)
            }
        }
        .animation(.easeOut(duration: 1.5), value: burst)
        .onAppear {
            burst = true
            // Reset and re-burst periodically
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    burst = false
                    particles = (0..<24).map { _ in CelebrationParticle() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        burst = true
                    }
                }
            }
        }
    }
}

private struct CelebrationParticle: Identifiable {
    let id = UUID()
    let endOffset: CGPoint
    let color: Color
    let size: CGFloat
    let opacity: Double

    init() {
        let angle = Double.random(in: 0...(2 * .pi))
        let distance = CGFloat.random(in: 40...80)
        endOffset = CGPoint(
            x: cos(angle) * distance,
            y: sin(angle) * distance
        )
        color = [Color.purple, .blue, .cyan, .green, .pink, .orange, .yellow].randomElement()!
        size = CGFloat.random(in: 3...6)
        opacity = Double.random(in: 0.6...1.0)
    }
}
