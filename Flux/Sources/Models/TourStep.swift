import SwiftUI

enum TourAnimationStyle {
    case pulse
    case bounce
    case shimmer
    case wave
    case burst
}

struct TourStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let animationStyle: TourAnimationStyle
}
