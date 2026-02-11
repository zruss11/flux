import SwiftUI

// MARK: - Waveform State

@Observable
class WaveformState {
    var barLevels: [Float] = Array(repeating: 0, count: 16)
    var isProcessing = false
}

// MARK: - Waveform View

struct WaveformView: View {
    @Bindable var state: WaveformState

    private let barCount = 16
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 24
    private let barCornerRadius: CGFloat = 2

    var body: some View {
        ZStack {
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = index < state.barLevels.count ? state.barLevels[index] : 0
                    RoundedRectangle(cornerRadius: barCornerRadius)
                        .fill(.white.opacity(0.9))
                        .frame(width: barWidth, height: barHeight(for: level))
                        .animation(
                            .spring(response: 0.15, dampingFraction: 0.6),
                            value: level
                        )
                }
            }
            .opacity(state.isProcessing ? 0.4 : 1)

            if state.isProcessing {
                processingOverlay
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    private func barHeight(for level: Float) -> CGFloat {
        max(minBarHeight, CGFloat(level) * maxBarHeight)
    }

    private var processingOverlay: some View {
        Text("Processing...")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .phaseAnimator([false, true]) { content, phase in
                content.opacity(phase ? 1.0 : 0.4)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
    }
}
