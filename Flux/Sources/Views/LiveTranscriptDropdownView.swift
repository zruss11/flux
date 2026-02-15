import SwiftUI

/// A dropdown view that displays live transcription text as it's being dictated.
/// Extends down from the notch like the ticker bar, but shows a growing text box
/// instead of scrolling text.
struct LiveTranscriptDropdownView: View {
    let transcript: String
    /// Width to match the island (including horizontal padding).
    var containerWidth: CGFloat = 260
    /// Maximum height before scrolling kicks in.
    var maxHeight: CGFloat = 120
    /// Corner radius for the dropdown.
    var cornerRadius: CGFloat = 14

    // MARK: - State

    @State private var isRevealed = false
    @State private var textHeight: CGFloat = 0

    private let minHeight: CGFloat = 36
    private let padding: CGFloat = 12

    /// Calculated height based on text content, capped at maxHeight.
    private var containerHeight: CGFloat {
        min(max(textHeight + padding * 2, minHeight), maxHeight)
    }

    /// Whether to show scrollbar (when text exceeds max height).
    private var needsScroll: Bool {
        textHeight + padding * 2 > maxHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Transcript text
            ScrollView {
                Text(transcript)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(padding)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear { textHeight = geo.size.height }
                                .onChange(of: transcript) { _, _ in
                                    textHeight = geo.size.height
                                }
                        }
                    )
            }
            .frame(height: containerHeight)
            .opacity(needsScroll ? 1 : 0) // Only show scrollview if needed

            // Non-scrolling text for short transcripts
            if !needsScroll {
                Text(transcript)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(padding)
            }
        }
        .frame(width: containerWidth, height: isRevealed ? containerHeight : 0)
        .clipped()
        .glassEffect(
            .regular,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .onAppear {
            // Animate in with a spring
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isRevealed = true
            }
        }
    }
}
