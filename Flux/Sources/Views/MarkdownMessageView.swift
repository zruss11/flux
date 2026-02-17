import MarkdownUI
import SwiftUI

struct MarkdownMessageView: View {
    let content: String

    /// Very large responses can lock the main thread during markdown parsing.
    /// Render plain text above this threshold to keep the UI responsive.
    private let markdownCharacterThreshold = 6_000
    private let markdownLineThreshold = 180

    private var shouldRenderAsPlainText: Bool {
        if content.count > markdownCharacterThreshold {
            return true
        }

        let lineCount = content.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }

        return lineCount > markdownLineThreshold && content.count > 2_500
    }

    var body: some View {
        if shouldRenderAsPlainText {
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        } else {
            Markdown(content)
                .markdownTheme(.flux)
                .textSelection(.enabled)
        }
    }
}
