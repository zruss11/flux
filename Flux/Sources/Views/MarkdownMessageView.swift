import MarkdownUI
import SwiftUI

struct MarkdownMessageView: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.flux)
            .textSelection(.enabled)
    }
}
