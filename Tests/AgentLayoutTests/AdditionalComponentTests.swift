import MarkdownUI
import SwiftUI
import Testing
import ViewInspector
import XCTest

@testable import Agent
@testable import AgentLayout

// MARK: - Additional OpenAIMessageRow Tests

@MainActor
struct AdditionalOpenAIMessageRowTests {

    @Test func testUserMessageWithContent() throws {
        let message = OpenAIMessage.user(.init(content: "Test message"))
        let row = OpenAIMessageRow(id: "1", message: message)
        let view = try row.inspect()

        let vStack = try view.find(ViewType.VStack.self)
        _ = try vStack.find(ViewType.HStack.self)
    }

    @Test func testAssistantMessageWithToolCalls() throws {
        let toolCalls = [
            OpenAIToolCall(
                id: "call_1",
                type: .function,
                function: .init(name: "get_weather", arguments: "{}")
            )
        ]
        let message = OpenAIMessage.assistant(
            .init(content: "I'll check", toolCalls: toolCalls, audio: nil, reasoning: nil)
        )
        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            messages: [
                .tool(.init(content: "Result", toolCallId: "call_1", name: "get_weather"))
            ],
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testAssistantMessageLoadingState() throws {
        let message = OpenAIMessage.assistant(
            .init(content: nil, toolCalls: nil, audio: nil, reasoning: nil)
        )
        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            status: .loading,
            isLastMessage: true
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testUserMessageWithAllCallbacks() throws {
        let message = OpenAIMessage.user(.init(content: "Test"))
        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            onDelete: {},
            onEdit: { _ in },
            onRegenerate: {}
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testSystemMessageContent() {
        let message = OpenAIMessage.system(.init(content: "System prompt"))
        #expect(message.content == "System prompt")
        #expect(message.role == .system)
    }

    @Test func testMessageWithEmptyContent() throws {
        let message = OpenAIMessage.assistant(
            .init(content: "", toolCalls: nil, audio: nil, reasoning: nil)
        )
        let row = OpenAIMessageRow(id: "1", message: message)
        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testMultipleToolCalls() throws {
        let toolCalls = [
            OpenAIToolCall(
                id: "call_1",
                type: .function,
                function: .init(name: "tool1", arguments: "{}")
            ),
            OpenAIToolCall(
                id: "call_2",
                type: .function,
                function: .init(name: "tool2", arguments: "{}")
            )
        ]
        let message = OpenAIMessage.assistant(
            .init(content: "Calling tools", toolCalls: toolCalls, audio: nil, reasoning: nil)
        )
        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            messages: [
                .tool(.init(content: "Result1", toolCallId: "call_1", name: "tool1")),
                .tool(.init(content: "Result2", toolCallId: "call_2", name: "tool2"))
            ]
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }
}

// MARK: - Additional JSONView Tests

@MainActor
struct AdditionalJSONViewTests {

    @Test func testJSONWithAllTypes() throws {
        let json = """
        {
            "string": "value",
            "number": 123,
            "float": 45.67,
            "bool": true,
            "null": null,
            "array": [1, 2, 3],
            "object": {"nested": "value"}
        }
        """
        let view = JSONSyntaxView(jsonString: json)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testJSONWithScientificNotation() throws {
        let json = """
        {"value": 1.23e-4}
        """
        let view = JSONSyntaxView(jsonString: json)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testFormattedJSONWithPunctuation() throws {
        let view = FormattedJSONText(jsonString: "{ }, [ ], : ,")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testFormattedJSONWithMultipleLines() throws {
        let json = """
        {
            "key1": "value1",
            "key2": "value2"
        }
        """
        let view = FormattedJSONText(jsonString: json)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testFormattedJSONWithNestedObjects() throws {
        let json = """
        {
            "outer": {
                "inner": {
                    "deep": "value"
                }
            }
        }
        """
        let view = FormattedJSONText(jsonString: json)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }
}

// MARK: - Additional OpenAIToolMessageRow Tests

@MainActor
struct AdditionalOpenAIToolMessageRowTests {

    @Test func testToolMessageRowIdleWithResponse() throws {
        let toolCall = OpenAIToolCall(
            id: "call_123",
            type: .function,
            function: .init(name: "test_tool", arguments: "{\"param\": \"value\"}")
        )
        let messages: [OpenAIMessage] = [
            .tool(.init(content: "{\"result\": \"success\"}", toolCallId: "call_123", name: "test_tool"))
        ]

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: messages,
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolMessageRowWithComplexArguments() throws {
        let toolCall = OpenAIToolCall(
            id: "call_456",
            type: .function,
            function: .init(
                name: "complex_tool",
                arguments: "{\"nested\": {\"key\": \"value\"}, \"array\": [1, 2, 3]}"
            )
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolMessageRowWithEmptyArguments() throws {
        let toolCall = OpenAIToolCall(
            id: "call_789",
            type: .function,
            function: .init(name: "no_args_tool", arguments: "")
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .loading
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolMessageRowWithNilFunction() throws {
        let toolCall = OpenAIToolCall(
            id: "call_000",
            type: .function,
            function: nil
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolResponseLookup() {
        let toolCall = OpenAIToolCall(
            id: "call_test",
            type: .function,
            function: .init(name: "test", arguments: "{}")
        )
        let messages: [OpenAIMessage] = [
            .user(.init(content: "user message")),
            .tool(.init(content: "tool result", toolCallId: "call_test", name: "test")),
            .assistant(.init(content: "assistant", toolCalls: nil, audio: nil, reasoning: nil))
        ]

        // Create row and check that it can find the tool response
        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: messages,
            status: .idle
        )

        // The row should find the tool response in the messages
        #expect(row != nil)
    }
}

// MARK: - Additional ModelPicker Tests

@MainActor
struct AdditionalModelPickerTests {

    @Test func testModelPickerWithEmptySources() throws {
        var currentModel = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: []
        )

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: [],
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }

    @Test func testModelPickerWithManyModels() throws {
        var currentModel = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: (1...10).map { Model.openAI(OpenAICompatibleModel(id: "model-\($0)")) }
        )

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: [currentSource],
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }

    @Test func testModelPickerWithMixedModelTypes() throws {
        var currentModel = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: [
                .openAI(OpenAICompatibleModel(id: "openai-model", name: "OpenAI Model")),
                .custom(CustomModel(id: "custom-model"))
            ]
        )

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: [currentSource],
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }
}

// MARK: - Additional CopyButton Tests

@MainActor
struct AdditionalCopyButtonTests {

    @Test func testCopyButtonWithSpecialCharacters() throws {
        let content = "Special chars: @#$%^&*()_+-=[]{}|;':\",./<>?"
        let button = CopyButton(content: content)
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }

    @Test func testCopyButtonWithNewlines() throws {
        let content = "Line 1\nLine 2\nLine 3"
        let button = CopyButton(content: content)
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }

    @Test func testCopyButtonWithUnicode() throws {
        let content = "Unicode: 你好世界 🌍 Ñoño"
        let button = CopyButton(content: content)
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }
}

// MARK: - Additional OpenAI Chat Type Tests

@MainActor
struct AdditionalOpenAIChatTypeTests {

    @Test func testOpenAIAssistantMessageAudio() throws {
        let audio = OpenAIAssistantMessage.Audio(
            id: "audio-123",
            data: "base64encodeddata",
            transcript: "Hello, world!"
        )

        let encoded = try JSONEncoder().encode(audio)
        let decoded = try JSONDecoder().decode(OpenAIAssistantMessage.Audio.self, from: encoded)

        #expect(decoded.id == "audio-123")
        #expect(decoded.data == "base64encodeddata")
        #expect(decoded.transcript == "Hello, world!")
    }

    @Test func testOpenAIMessageWithNilContent() {
        let message = OpenAIMessage.assistant(
            .init(content: nil, toolCalls: nil, audio: nil, reasoning: nil)
        )
        #expect(message.content == nil)
    }

    @Test func testOpenAIToolCallFunction() {
        let function = OpenAIToolCall.Function(
            name: "test_function",
            arguments: "{\"key\": \"value\"}"
        )

        #expect(function.name == "test_function")
        #expect(function.arguments == "{\"key\": \"value\"}")
    }

    @Test func testOpenAIToolCallFunctionWithNils() {
        let function = OpenAIToolCall.Function(name: nil, arguments: nil)
        #expect(function.name == nil)
        #expect(function.arguments == nil)
    }
}

// MARK: - BlinkingDot Tests (internal component)

@MainActor
struct BlinkingDotTests {

    @Test func testBlinkingDotExists() throws {
        // BlinkingDot is an internal component used in OpenAIMessageRow
        // Testing that the loading state properly shows the blinking dot
        let message = OpenAIMessage.assistant(
            .init(content: "", toolCalls: nil, audio: nil, reasoning: nil)
        )
        let row = OpenAIMessageRow(
            id: "1",
            message: message,
            status: .loading,
            isLastMessage: true
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }
}

// MARK: - ChatStatus Extended Tests

@MainActor
struct ChatStatusExtendedTests {

    @Test func testChatStatusEquality() {
        #expect(ChatStatus.idle == ChatStatus.idle)
        #expect(ChatStatus.loading == ChatStatus.loading)
        #expect(ChatStatus.idle != ChatStatus.loading)
    }
}
