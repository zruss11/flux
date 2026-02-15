import SwiftUI

struct StatusChipCapsule<Content: View>: View {
    var fillOpacity: Double
    var strokeOpacity: Double
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(fillOpacity))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
    }
}

