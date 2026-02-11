@preconcurrency import MarkdownUI
import SwiftUI

extension Theme {
    @MainActor static let flux = Theme()
        .text {
            ForegroundColor(.white)
            FontSize(13)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.white.opacity(0.9))
            BackgroundColor(Color.white.opacity(0.1))
        }
        .link {
            ForegroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(17)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 10, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading4 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                    ForegroundColor(.white)
                }
                .markdownMargin(top: 6, bottom: 2)
        }
        .heading5 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.medium)
                    FontSize(13)
                    ForegroundColor(.white.opacity(0.9))
                }
                .markdownMargin(top: 4, bottom: 2)
        }
        .heading6 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.medium)
                    FontSize(12)
                    ForegroundColor(.white.opacity(0.8))
                }
                .markdownMargin(top: 4, bottom: 2)
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                        ForegroundColor(.white.opacity(0.9))
                    }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
            .markdownMargin(top: 4, bottom: 4)
        }
        .blockquote { configuration in
            configuration.label
                .padding(.leading, 12)
                .markdownTextStyle {
                    ForegroundColor(.white.opacity(0.7))
                    FontStyle(.italic)
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 3)
                }
                .markdownMargin(top: 4, bottom: 4)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
}
