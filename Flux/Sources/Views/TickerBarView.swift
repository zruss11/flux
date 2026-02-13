import SwiftUI

/// Animated stock-ticker–style text bar that slides below the island to display
/// a one-line CI (or generic) notification message.
struct TickerBarView: View {
    let message: String
    /// Width to match the closed island.
    var barWidth: CGFloat = 260

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var appeared = false

    /// Total scroll distance: start off-screen right, scroll until fully off-screen left.
    private var scrollDistance: CGFloat {
        barWidth + textWidth
    }

    /// Duration scales with text length so speed feels consistent.
    private var scrollDuration: Double {
        max(4.0, Double(scrollDistance) / 60.0)
    }

    var body: some View {
        ZStack {
            // Clipping container at the island width
            Rectangle()
                .fill(.clear)
                .frame(width: barWidth, height: 28)
                .clipped()
                .overlay {
                    // Scrolling text
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        textWidth = geo.size.width
                                    }
                            }
                        )
                        .offset(x: offset)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(width: barWidth, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
        .onAppear {
            // Start from right edge
            offset = barWidth / 2
            // Small delay to let geometry reader measure, then start scrolling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.linear(duration: scrollDuration)) {
                    offset = -(barWidth / 2 + textWidth)
                }
            }
        }
    }
}
