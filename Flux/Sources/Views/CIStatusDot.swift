import SwiftUI

/// Compact animated dot that shows aggregate CI status in the closed notch.
struct CIStatusDot: View {
    let status: CIAggregateStatus

    @State private var pulse = false

    private var dotColor: Color {
        switch status {
        case .idle:    return .clear
        case .passing: return .green
        case .failing: return .red
        case .running: return .orange
        case .unknown: return .gray
        }
    }

    private var glowOpacity: Double {
        switch status {
        case .idle:    return 0
        case .passing: return pulse ? 0.5 : 0.2
        case .failing: return pulse ? 0.7 : 0.25
        case .running: return pulse ? 0.6 : 0.2
        case .unknown: return 0.1
        }
    }

    private var dotScale: CGFloat {
        switch status {
        case .failing: return pulse ? 1.15 : 0.9
        case .running: return pulse ? 1.1 : 0.92
        case .passing: return pulse ? 1.05 : 0.95
        default:       return 1.0
        }
    }

    private var isAnimating: Bool {
        status == .passing || status == .failing || status == .running
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(dotColor.opacity(glowOpacity))
                .frame(width: 14, height: 14)
                .blur(radius: 2)

            // Core dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .scaleEffect(dotScale)
                .shadow(color: dotColor.opacity(0.6), radius: isAnimating ? 4 : 0)
        }
        .opacity(status == .idle ? 0 : 1)
        .animation(
            isAnimating
                ? .easeInOut(duration: status == .failing ? 0.9 : 1.4)
                    .repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
            value: pulse
        )
        .onAppear { pulse = isAnimating }
        .onChange(of: status) { _, _ in
            pulse = isAnimating
        }
    }
}
