import SwiftUI

/// Animated stock-ticker–style text bar that extends organically from the
/// bottom of the island. Designed to look like the island itself is growing
/// a "chin" that reveals scrolling text, then retracting.
struct TickerBarView: View {
    let message: String
    /// Width to match the closed island (including horizontal padding).
    var barWidth: CGFloat = 260
    /// Bottom corner radius — should match the island's bottom radius.
    var cornerRadius: CGFloat = 14
    /// Total visible duration before the bar retracts.
    var displayDuration: Double = 6.0

    // MARK: - State

    @State private var textWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var revealed = false
    @State private var dismissed = false

    private let barHeight: CGFloat = 28

    /// Total scroll distance: from right edge off-screen to left edge off-screen.
    private var scrollDistance: CGFloat {
        barWidth + textWidth
    }

    /// Speed-based duration so text always scrolls at a consistent pace.
    private var scrollDuration: Double {
        max(3.5, Double(scrollDistance) / 55.0)
    }

    var body: some View {
        // Container — flat top, rounded bottom, matching island aesthetic.
        ZStack {
            // Scrolling text — clipped to the bar width
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize()
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { textWidth = geo.size.width }
                    }
                )
                .offset(x: scrollOffset)
        }
        .frame(width: barWidth, height: barHeight)
        .clipped()
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(.black)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        // The "extrude" effect: clip height from 0 → barHeight
        .mask(
            Rectangle()
                .frame(height: revealed ? barHeight : 0)
                .frame(maxHeight: barHeight, alignment: .top)
        )
        // Subtle glow underneath
        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
        .onAppear {
            // Phase 1: Extend the bar downward (organic growth)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                revealed = true
            }

            // Phase 2: Start scrolling text after the bar has extended
            scrollOffset = barWidth / 2 + 10
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.linear(duration: scrollDuration)) {
                    scrollOffset = -(textWidth + barWidth / 2 + 10)
                }
            }

            // Phase 3: Retract the bar back up after display duration
            DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration - 0.5) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    revealed = false
                }
            }
        }
    }
}
