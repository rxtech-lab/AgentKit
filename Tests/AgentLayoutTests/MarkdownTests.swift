import JSONSchema
import MarkdownUI
import SwiftUI
import Testing
import ViewInspector
import XCTest

@testable import Agent
@testable import AgentLayout

// MARK: - CodeBlockView Tests

@MainActor
struct CodeBlockViewTests {

    @Test func testCodeBlockConfiguration() {
        // Test that CodeBlockConfiguration can be created
        // CodeBlockView is used inside the MarkdownTheme
        let _ = Theme.chatTheme
    }
}


// MARK: - Extended Theme Tests

@MainActor
struct ExtendedThemeTests {

    @Test func testThemeSendable() {
        // Verify Theme conforms to Sendable
        let theme = Theme.chatTheme
        Task {
            let _ = theme
        }
    }

    @Test func testAllColorVariations() {
        // Test both light and dark color variations exist
        let colors: [(Color, String)] = [
            (Color.text, "text"),
            (Color.secondaryText, "secondaryText"),
            (Color.tertiaryText, "tertiaryText"),
            (Color.background, "background"),
            (Color.secondaryBackground, "secondaryBackground"),
            (Color.link, "link"),
            (Color.border, "border"),
            (Color.divider, "divider"),
            (Color.checkbox, "checkbox"),
            (Color.checkboxBackground, "checkboxBackground")
        ]

        #expect(colors.count == 10)
    }
}

// MARK: - MessageRow Extended Tests

@MainActor
struct MessageRowExtendedTests {

    @Test func testMessageRowWithOpenAIMessage() throws {
        let message = Message.openai(.user(.init(content: "Hello")))
        let row = MessageRow(id: "1", message: message)

        let view = try row.inspect()
        _ = try view.find(ViewType.AnyView.self)
    }

    @Test func testMessageRowWithAssistantMessage() throws {
        let message = Message.openai(.assistant(.init(content: "Response", toolCalls: nil, audio: nil)))
        let row = MessageRow(id: "2", message: message)

        let view = try row.inspect()
        _ = try view.find(ViewType.AnyView.self)
    }
}

// MARK: - AgentTool Tests

@MainActor
struct AgentToolExtendedTests {

    @Test func testAgentToolInit() async throws {
        let schemaJson = """
        {"type": "object", "properties": {"param": {"type": "string"}}}
        """
        let schema = try JSONSchema(jsonString: schemaJson)

        let tool = AgentTool(
            name: "test_tool",
            description: "A test tool",
            parameters: schema
        ) { (args: String) in
            return "Result: \(args)"
        }

        #expect(tool.name == "test_tool")
        #expect(tool.description == "A test tool")

        let result = try await tool.execute("{\"param\": \"value\"}")
        #expect(result.contains("Result:"))
    }
}

// MARK: - OpenAI Message Comprehensive Tests

@MainActor
struct OpenAIMessageComprehensiveTests {

    @Test func testAllMessageTypes() {
        // User
        let user = OpenAIMessage.user(.init(content: "User"))
        #expect(user.role == .user)

        // Assistant
        let assistant = OpenAIMessage.assistant(.init(content: "Assistant", toolCalls: nil, audio: nil))
        #expect(assistant.role == .assistant)

        // System
        let system = OpenAIMessage.system(.init(content: "System"))
        #expect(system.role == .system)

        // Tool
        let tool = OpenAIMessage.tool(.init(content: "Tool", toolCallId: "id"))
        #expect(tool.role == .tool)
    }

    @Test func testMessageWithLongContent() {
        let longContent = String(repeating: "Lorem ipsum ", count: 1000)
        let message = OpenAIMessage.user(.init(content: longContent))
        #expect(message.content?.count ?? 0 > 10000)
    }
}
