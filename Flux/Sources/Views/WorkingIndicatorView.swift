import SwiftUI

struct WorkingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Image(systemName: "gear.badge.checkmark")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .scaleEffect(1.2)
            .symbolRenderingMode(.hierarchical)
            .animation(
                reduceMotion 
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: false)
                    : .linear(duration: 2.0).repeatForever(autoreverses: false),
                value: true
            )
    }
}