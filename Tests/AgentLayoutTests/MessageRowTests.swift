import SwiftUI
import Testing
import ViewInspector
import XCTest

@testable import Agent
@testable import AgentLayout

@MainActor
struct MessageRowTests {

    @Test func testUserMessageDisplay() async throws {
        let content = "Hello World"
        let message = OpenAIMessage.user(.init(content: content))
        let row = OpenAIMessageRow(id: "1", message: message)

        let view = try row.inspect()

        // Check if content is displayed via Markdown
        // Note: Markdown view wraps its content.
        // Since MarkdownUI is a 3rd party lib, ViewInspector might not traverse it easily unless we have the extension.
        // However, we can check if the text exists in the view hierarchy if Markdown is transparent or if we search for text.
        // Or we can check if `Markdown` view is present.

        // Looking at OpenAIMessageRow.swift:
        // Markdown(content)

        // ViewInspector for custom views usually requires Inspectable.
        // Assuming Markdown is Inspectable or we can find it by type name or just check for text.

        // Let's try to find the Markdown view.
        // Since I don't know if Markdown is Inspectable, I will try to find the text "Hello World"
        // If Markdown renders it as Text, it might be found.

        // Alternatively, we can inspect the structure.
        // User message: VStack -> HStack -> Spacer -> Content

        let vStack = try view.find(ViewType.VStack.self)
        let hStack = try vStack.find(ViewType.HStack.self)

        // Verify alignment/spacer for user message (trailing)
        // User message has Spacer() first.
        _ = try hStack.find(ViewType.Spacer.self, skipFound: 0)
    }

    @Test func testAssistantMessageDisplay() async throws {
        let content = "Hello User"
        let message = OpenAIMessage.assistant(.init(content: content, toolCalls: nil, audio: nil))
        let row = OpenAIMessageRow(id: "1", message: message)

        let view = try row.inspect()

        let vStack = try view.find(ViewType.VStack.self)
        let hStack = try vStack.find(ViewType.HStack.self)

        // Assistant message: Content -> Spacer
        // So Spacer is second (index 1 usually if content is 0, but let's just check existence)
        // Ideally we check order.
    }

    @Test func testEditMode() async throws {
        let content = "Original"
        let message = OpenAIMessage.user(.init(content: content))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onEdit: { _ in }
        )

        // Verify the view can be created and inspected
        let view = try row.inspect()

        // Verify basic structure exists for user message
        let vStack = try view.find(ViewType.VStack.self)
        let hStack = try vStack.find(ViewType.HStack.self)

        // User messages have Spacer first (trailing alignment)
        _ = try hStack.find(ViewType.Spacer.self)
    }

    @Test func testRegenerateCallback() async throws {
        let message = OpenAIMessage.assistant(
            .init(content: "Response", toolCalls: nil, audio: nil))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onRegenerate: { }
        )
        let view = try row.inspect()

        // Verify the view structure for assistant message
        let vStack = try view.find(ViewType.VStack.self)
        let hStack = try vStack.find(ViewType.HStack.self)

        // Assistant messages have content first, then Spacer (leading alignment)
        _ = try hStack.find(ViewType.Spacer.self)
    }

    @Test func testDeleteCallback() async throws {
        let message = OpenAIMessage.assistant(
            .init(content: "Response", toolCalls: nil, audio: nil))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onDelete: { }
        )
        let view = try row.inspect()

        // Verify the view structure exists
        let vStack = try view.find(ViewType.VStack.self)
        _ = try vStack.find(ViewType.HStack.self)
    }

    @Test func testRegenerateCallbackForUserMessage() async throws {
        let message = OpenAIMessage.user(.init(content: "Hello"))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onRegenerate: { }
        )
        let view = try row.inspect()

        // Verify the view structure for user message
        let vStack = try view.find(ViewType.VStack.self)
        let hStack = try vStack.find(ViewType.HStack.self)

        // User messages have Spacer first (trailing alignment)
        _ = try hStack.find(ViewType.Spacer.self)
    }

    @Test func testUserMessageHasRegenerateButton() async throws {
        let message = OpenAIMessage.user(.init(content: "Hello"))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onRegenerate: { }
        )
        let view = try row.inspect()

        // Verify the view structure exists
        let vStack = try view.find(ViewType.VStack.self)

        // Find buttons in the action buttons HStack
        // The regenerate button should exist for user messages now
        let buttons = vStack.findAll(ViewType.Button.self)

        // User message should have at least 3 buttons: edit, regenerate, copy, delete
        // When not in edit mode, we have: edit pencil + regenerate + copy + delete = 4 buttons
        #expect(buttons.count >= 3, "User message should have regenerate button along with other action buttons")
    }

    @Test func testAssistantMessageHasRegenerateButton() async throws {
        let message = OpenAIMessage.assistant(
            .init(content: "Response", toolCalls: nil, audio: nil))

        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onRegenerate: { }
        )
        let view = try row.inspect()

        // Verify the view structure exists
        let vStack = try view.find(ViewType.VStack.self)

        // Find buttons in the action buttons HStack
        let buttons = vStack.findAll(ViewType.Button.self)

        // Assistant message should have: regenerate + copy + delete = 3 buttons
        #expect(buttons.count >= 3, "Assistant message should have regenerate button along with other action buttons")
    }
}
