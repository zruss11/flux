import SwiftUI

struct FluxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
