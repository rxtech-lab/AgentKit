//
//  MarkdownStripperTests.swift
//  AgentLayout
//
//  Created by Claude on 12/2/25.
//

import Testing

@testable import AgentLayout

struct MarkdownStripperTests {

    @Test func testStripBoldDoubleAsterisk() {
        #expect(MarkdownStripper.stripMarkdown("**bold**") == "bold")
    }

    @Test func testStripBoldDoubleUnderscore() {
        #expect(MarkdownStripper.stripMarkdown("__bold__") == "bold")
    }

    @Test func testStripItalicAsterisk() {
        #expect(MarkdownStripper.stripMarkdown("*italic*") == "italic")
    }

    @Test func testStripItalicUnderscore() {
        #expect(MarkdownStripper.stripMarkdown("_italic_") == "italic")
    }

    @Test func testStripCombinedBoldAndItalic() {
        #expect(MarkdownStripper.stripMarkdown("**bold** and *italic*") == "bold and italic")
    }

    @Test func testStripInlineCode() {
        #expect(MarkdownStripper.stripMarkdown("`code`") == "code")
    }

    @Test func testStripLinks() {
        #expect(MarkdownStripper.stripMarkdown("[text](https://example.com)") == "text")
    }

    @Test func testStripImages() {
        #expect(MarkdownStripper.stripMarkdown("![alt text](https://example.com/image.png)") == "alt text")
    }

    @Test func testStripH1Header() {
        #expect(MarkdownStripper.stripMarkdown("# Header") == "Header")
    }

    @Test func testStripH2Header() {
        #expect(MarkdownStripper.stripMarkdown("## Header") == "Header")
    }

    @Test func testStripH3Header() {
        #expect(MarkdownStripper.stripMarkdown("### Header") == "Header")
    }

    @Test func testPlainTextUnchanged() {
        #expect(MarkdownStripper.stripMarkdown("plain text") == "plain text")
    }

    @Test func testEmptyString() {
        #expect(MarkdownStripper.stripMarkdown("") == "")
    }

    @Test func testIncompleteMarkdownBoldStart() {
        // Should handle incomplete markdown gracefully - removes leading **
        let result = MarkdownStripper.stripMarkdown("**incomplete")
        #expect(result == "incomplete")
    }

    @Test func testIncompleteMarkdownBoldEnd() {
        // Should handle incomplete markdown gracefully - removes trailing **
        let result = MarkdownStripper.stripMarkdown("incomplete**")
        #expect(result == "incomplete")
    }

    @Test func testStrikethrough() {
        #expect(MarkdownStripper.stripMarkdown("~~strikethrough~~") == "strikethrough")
    }

    @Test func testComplexMarkdown() {
        let input = "**Bold** text with *italic* and `code` plus [link](url)"
        let expected = "Bold text with italic and code plus link"
        #expect(MarkdownStripper.stripMarkdown(input) == expected)
    }

    @Test func testPreparingExample() {
        // This is the actual use case from the bug report
        #expect(MarkdownStripper.stripMarkdown("**Preparing**") == "Preparing")
    }

    @Test func testNestedFormatting() {
        // Test bold containing italic-like content
        #expect(MarkdownStripper.stripMarkdown("**bold text**") == "bold text")
    }

    @Test func testMultipleLinks() {
        let input = "[link1](url1) and [link2](url2)"
        let expected = "link1 and link2"
        #expect(MarkdownStripper.stripMarkdown(input) == expected)
    }

    @Test func testUnderscoreInWord() {
        // Underscores within words should be preserved (like snake_case)
        let result = MarkdownStripper.stripMarkdown("snake_case_variable")
        #expect(result == "snake_case_variable")
    }
}
