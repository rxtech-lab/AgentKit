import MarkdownUI
import Splash
import SwiftUI

struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let syntaxHighlighter: SyntaxHighlighter<TextOutputFormat>

    init(theme: Splash.Theme) {
        self.syntaxHighlighter = SyntaxHighlighter(format: TextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        return self.syntaxHighlighter.highlight(content)
    }
}

extension CodeSyntaxHighlighter where Self == SplashCodeSyntaxHighlighter {
    static func splash(theme: Splash.Theme) -> Self {
        SplashCodeSyntaxHighlighter(theme: theme)
    }
}

struct TextOutputFormat: OutputFormat {
    private let theme: Splash.Theme

    init(theme: Splash.Theme) {
        self.theme = theme
    }

    func makeBuilder() -> Builder {
        Builder(theme: self.theme)
    }
}

extension TextOutputFormat {
    struct Builder: OutputBuilder {
        private let theme: Splash.Theme
        private var accumulatedText: [Text]

        fileprivate init(theme: Splash.Theme) {
            var theme = theme

            #if canImport(UIKit)
            theme.plainTextColor = .label
            #elseif canImport(AppKit)
            theme.plainTextColor = .textColor
            #endif
            theme.tokenColors[.keyword] = .blue
            theme.tokenColors[.string] = .blue
            theme.tokenColors[.comment] = .gray
            theme.tokenColors[.number] = .purple
            theme.tokenColors[.call] = .orange

            self.theme = theme
            self.accumulatedText = []
        }

        mutating func addToken(_ token: String, ofType type: TokenType) {
            #if canImport(UIKit)
            let color = self.theme.tokenColors[type] ?? .label
            #elseif canImport(AppKit)
            let color = self.theme.tokenColors[type] ?? .textColor
            #endif
            #if canImport(UIKit)
            self.accumulatedText.append(Text(token).foregroundColor(.init(uiColor: color)))
            #elseif canImport(AppKit)
            self.accumulatedText.append(Text(token).foregroundColor(.init(nsColor: color)))
            #endif
        }

        mutating func addPlainText(_ text: String) {
            #if canImport(UIKit)
            self.accumulatedText.append(
                Text(text).foregroundColor(.init(uiColor: self.theme.plainTextColor))
            )
            #elseif canImport(AppKit)
            self.accumulatedText.append(
                Text(text).foregroundColor(.init(nsColor: self.theme.plainTextColor))
            )
            #endif
        }

        mutating func addWhitespace(_ whitespace: String) {
            self.accumulatedText.append(Text(whitespace))
        }

        func build() -> Text {
            self.accumulatedText.reduce(Text(""), +)
        }
    }
}
