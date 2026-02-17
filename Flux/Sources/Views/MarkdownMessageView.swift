import MarkdownUI
import SwiftUI

struct MarkdownMessageView: View {
    let content: String

    /// Very large responses can lock the main thread during markdown parsing.
    /// Render plain text above this threshold to keep the UI responsive.
    private let markdownCharacterThreshold = 18_000

    var body: some View {
        if content.count > markdownCharacterThreshold {
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
