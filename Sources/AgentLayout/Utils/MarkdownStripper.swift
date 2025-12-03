//
//  MarkdownStripper.swift
//  AgentLayout
//
//  Created by Claude on 12/2/25.
//

import Foundation

/// Utility for stripping markdown syntax from text
enum MarkdownStripper {
    /// Strips common markdown syntax from text and returns plain text
    /// - Parameter text: The markdown-formatted text
    /// - Returns: Plain text with markdown syntax removed
    static func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove bold: **text** or __text__
        result = result.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove italic: *text* or _text_
        result = result.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove strikethrough: ~~text~~
        result = result.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove inline code: `text`
        result = result.replacingOccurrences(
            of: #"`(.+?)`"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove headers: # text (at start of string or line)
        result = result.replacingOccurrences(
            of: #"(?m)^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )

        // Remove images: ![alt](url) -> alt (before links to avoid conflict)
        result = result.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove links: [text](url) -> text
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove any remaining unmatched markdown characters (e.g., incomplete **)
        // This handles cases like "**incomplete" where there's no closing **
        result = result.replacingOccurrences(
            of: #"^\*\*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\*\*$"#,
            with: "",
            options: .regularExpression
        )

        return result
    }
}
