import SwiftUI

enum StatusChipStyle {
    static let defaultFillOpacity: Double = 0.06
    static let defaultStrokeOpacity: Double = 0.1

    static let warningFillOpacity: Double = 0.10
    static let warningStrokeOpacity: Double = 0.2

    static let criticalFillOpacity: Double = 0.12
    static let criticalStrokeOpacity: Double = 0.28
}

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

