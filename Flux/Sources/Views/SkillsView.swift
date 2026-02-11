import SwiftUI
import SpriteKit

struct SkillsView: View {
    @Binding var isPresented: Bool
    var onSkillSelected: (Skill) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showDot1 = false
    @State private var showDot2 = false
    @State private var showDot3 = false
    @State private var showBubble = false
    @State private var scene: SkillBubbleScene?
    @State private var accelerometer = AccelerometerService()
    @State private var skills: [Skill] = []
    @State private var installingSkillId: UUID?

    private var sceneHeight: CGFloat {
        skills.count > 16 ? 280 : 220
    }

    var body: some View {
        VStack(spacing: 4) {
            if isPresented {
                // Thought bubble container
                thoughtBubble
                    .scaleEffect(showBubble ? 1.0 : 0.3)
                    .opacity(showBubble ? 1.0 : 0.01)

                // Connector dots (bottom to top: smallest to largest)
                connectorDots
            }

            // Skills pill button
            skillsPill
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                openSequence()
            } else {
                closeSequence()
            }
        }
        .onKeyPress(.escape) {
            if isPresented {
                isPresented = false
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Thought Bubble

    private var thoughtBubble: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .frame(height: sceneHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            } else if skills.isEmpty && isPresented {
                Text("No skills available")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 80)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Connector Dots

    private var connectorDots: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 10, height: 10)
                .scaleEffect(showDot1 ? 1.0 : 0.01)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 7, height: 7)
                .scaleEffect(showDot2 ? 1.0 : 0.01)

            Circle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 5, height: 5)
                .scaleEffect(showDot3 ? 1.0 : 0.01)
        }
    }

    // MARK: - Skills Pill

    private var skillsPill: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Skills")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Animation Sequences

    private func openSequence() {
        print("[SkillsView] openSequence called, isPresented=\(isPresented)")
        Task {
            let loaded = await SkillsLoader.loadSkillsWithRecommendations()
            print("[SkillsView] Loaded \(loaded.count) skills, setting state")
            await MainActor.run {
                skills = loaded
                createScene()
            }
        }
    }

    private func createScene() {
        guard !skills.isEmpty else { return }

        let sceneSize = CGSize(width: 440, height: sceneHeight)
        let newScene = SkillBubbleScene(size: sceneSize)
        newScene.scaleMode = .resizeFill
        newScene.backgroundColor = .clear
        newScene.reduceMotion = reduceMotion
        newScene.skills = skills
        newScene.onSkillTapped = { skill in
            if skill.isInstalled {
                onSkillSelected(skill)
            } else {
                installSkill(skill)
            }
        }
        scene = newScene

        if accelerometer.isAvailable {
            accelerometer.start()
        }

        let dotAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.7)

        let bubbleAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.6, dampingFraction: 0.72)

        if reduceMotion {
            withAnimation(dotAnimation) {
                showDot1 = true
                showDot2 = true
                showDot3 = true
                showBubble = true
            }
        } else {
            // Staggered connector dots
            withAnimation(dotAnimation) {
                showDot3 = true
            }
            withAnimation(dotAnimation.delay(0.05)) {
                showDot2 = true
            }
            withAnimation(dotAnimation.delay(0.1)) {
                showDot1 = true
            }
            // Thought bubble
            withAnimation(bubbleAnimation.delay(0.15)) {
                showBubble = true
            }
        }

        // Wire up accelerometer gravity updates
        if accelerometer.isAvailable {
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { timer in
                guard isPresented else {
                    timer.invalidate()
                    return
                }
                scene?.updateGravity(accelerometer.gravity)
            }
        }
    }

    private func closeSequence() {
        accelerometer.stop()

        let bubbleAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.35, dampingFraction: 0.85)

        let dotAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.7)

        if reduceMotion {
            withAnimation(bubbleAnimation) {
                showBubble = false
                showDot1 = false
                showDot2 = false
                showDot3 = false
            }
        } else {
            withAnimation(bubbleAnimation) {
                showBubble = false
            }
            withAnimation(dotAnimation.delay(0.05)) {
                showDot1 = false
            }
            withAnimation(dotAnimation.delay(0.1)) {
                showDot2 = false
            }
            withAnimation(dotAnimation.delay(0.15)) {
                showDot3 = false
            }
        }

        // Clean up scene after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !isPresented {
                scene = nil
            }
        }
    }

    // MARK: - Skill Installation

    private func installSkill(_ skill: Skill) {
        guard installingSkillId == nil else { return }
        installingSkillId = skill.id

        Task {
            do {
                try await SkillInstaller.install(directoryName: skill.directoryName)
                let reloaded = await SkillsLoader.loadSkillsWithRecommendations()
                await MainActor.run {
                    skills = reloaded
                    installingSkillId = nil
                    createScene()
                }
            } catch {
                print("[SkillsView] Failed to install skill: \(error)")
                await MainActor.run {
                    installingSkillId = nil
                }
            }
        }
    }
}
