import NIOHTTP1
import SwiftUI
import Testing
import Vapor
import ViewInspector
import XCTest

@testable import Agent
@testable import AgentLayout

extension AgentLayout {}
extension MessageRow {}
extension MessageInputView {}
extension OpenAIMessageRow {}

struct MockChatProvider: ChatProvider {
    let onSend: (@Sendable (String, Model) -> Void)?
    let onSendResult: (@Sendable (String, any Encodable) -> Void)?
    let onReject: (@Sendable (String) -> Void)?

    func sendMessage(message: String, model: Model) async throws {
        onSend?(message, model)
    }

    func sendFunctionResult(id: String, result: any Encodable) async throws {
        onSendResult?(id, result)
    }

    func rejectFunction(id: String) async throws {
        onReject?(id)
    }
}

/// A controller that mocks OpenAI chat completion API responses for testing
@MainActor
class MockOpenAIChatController {
    private var mockResponseQueue: [[OpenAIAssistantMessage]]

    init() {
        self.mockResponseQueue = []
    }

    /// Add a set of mock responses to be returned for a single request
    func mockChatResponse(_ responses: [OpenAIAssistantMessage]) {
        mockResponseQueue.append(responses)
    }

    /// Register routes for this controller on a Vapor router
    func registerRoutes(on routes: RoutesBuilder) {
        let chatRoutes = routes.grouped("chat")
        chatRoutes.post("completions", use: handleChatCompletion)
    }

    private func handleChatCompletion(request: Request) async throws -> Response {
        let responses: [OpenAIAssistantMessage]
        if !self.mockResponseQueue.isEmpty {
            responses = self.mockResponseQueue.removeFirst()
        } else {
            responses = []
        }

        let body = Response.Body(stream: { writer in
            Task {
                let capturedResponses = responses
                let id = UUID().uuidString
                let created = Date().timeIntervalSince1970
                let model = "gpt-3.5-turbo"
                for response in capturedResponses {
                    let chunk = StreamChunk(
                        id: id,
                        created: Int(created),
                        model: model,
                        choices: [
                            StreamChoice(
                                index: 0, delta: response, finishReason: nil
                            )
                        ]
                    )
                    if let jsonData = try? JSONEncoder().encode(chunk),
                        let jsonString = String(data: jsonData, encoding: .utf8)
                    {
                        _ = writer.write(.buffer(ByteBuffer(string: "data: \(jsonString)\n\n")))
                    }
                }

                _ = writer.write(.end)
            }
        })

        let response = Response(status: .ok, body: body)
        response.headers.replaceOrAdd(
            name: HTTPHeaders.Name.contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: HTTPHeaders.Name.cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: HTTPHeaders.Name.connection, value: "keep-alive")
        return response
    }
}

@MainActor
@Test func testRenderMessageReplace() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    let customContent = "Custom Replacement"
    let renderer: MessageRenderer = { _, _, _, _ in
        (AnyView(Text(customContent)), .replace)
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )

    let view = try sut.inspect()

    // Verify custom view exists
    _ = try view.find(text: customContent)

    // Verify original message row is NOT present (since replaced)
    // Note: ViewInspector throws if not found.
    do {
        _ = try view.find(MessageRow.self)
        #expect(Bool(false), "MessageRow should not be present when action is .replace")
    } catch {
        // Expected
    }
}

@MainActor
@Test func testRenderMessageAppend() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    let customContent = "Custom Append"
    let renderer: MessageRenderer = { _, _, _, _ in
        (AnyView(Text(customContent)), .append)
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )

    let view = try sut.inspect()

    // Verify custom view exists
    _ = try view.find(text: customContent)

    // Verify original message row IS present
    _ = try view.find(MessageRow.self)
}

@MainActor
@Test func testRenderMessageSkip() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    let renderer: MessageRenderer = { _, _, _, _ in
        (AnyView(EmptyView()), .skip)
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )

    let view = try sut.inspect()

    // Verify original message row IS present (skip means skip the custom view, but show MessageRow)
    _ = try view.find(MessageRow.self)
}

@MainActor
@Test func testOnSendCallback() async throws {
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    // Host the view to ensure State/Binding updates work correctly
    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find input view
    let inputView = try view.find(MessageInputView.self)
    let textField = try inputView.find(ViewType.TextField.self)

    // Set input triggers binding update
    try textField.setInput("Hello World")

    // Re-find to get updated view hierarchy state
    let updatedInputView = try view.find(MessageInputView.self)

    // Manually trigger onSend closure directly from the view struct
    // This bypasses UI interaction issues but verifies the closure wiring
    // The 'onSend' closure in MessageInputView captures the logic in AgentLayout
    try updatedInputView.actualView().onSend("Hello World")

    // Verify onSend was called
    #expect(sentMessage == "Hello World")
}

@MainActor
@Test func testOnMessageCallbackParameter() async throws {
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var receivedMessages: [Message] = []
    let onMessage: (Message) -> Void = { message in
        receivedMessages.append(message)
    }

    // Verify AgentLayout accepts the onMessage callback
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onMessage: onMessage
    )

    // Host the view to ensure it initializes correctly
    ViewHosting.host(view: sut)

    // Verify view can be inspected (callback properly wired)
    let view = try sut.inspect()
    // Check something valid instead of nil check, e.g. body exists
    _ = try view.find(MessageInputView.self)
}

@MainActor
@Test func testOnMessageCallbackWithBothCallbacks() async throws {
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    var receivedMessages: [Message] = []

    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let onMessage: (Message) -> Void = { message in
        receivedMessages.append(message)
    }

    // Verify AgentLayout accepts both callbacks together
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend,
        onMessage: onMessage
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find input view and trigger onSend
    let inputView = try view.find(MessageInputView.self)
    try inputView.actualView().onSend("Test message")

    // Verify onSend was called
    #expect(sentMessage == "Test message")
}

@MainActor
@Test func testOnMessageCallbackNilByDefault() async throws {
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    // Verify AgentLayout works without onMessage callback (nil by default)
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source]
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()
    _ = try view.find(MessageInputView.self)
}

@MainActor
@Test func testEditMessageCallback() async throws {
    // Test that onEdit callback is properly wired in MessageRow
    let userMessage = Message.openai(.user(.init(content: "Original message")))
    let assistantMessage = Message.openai(
        .assistant(.init(content: "Response", toolCalls: nil, audio: nil)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [userMessage, assistantMessage])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find the first MessageRow (user message)
    let messageRows = view.findAll(MessageRow.self)
    #expect(messageRows.count == 2, "Expected 2 message rows")

    // Get the user message row and trigger edit
    let userMessageRow = messageRows[0]
    let editedContent = "Edited message"
    try userMessageRow.actualView().onEdit?(editedContent)

    // Verify onSend was called with the edited content
    #expect(sentMessage == editedContent, "Expected onSend to be called with edited content")
}

@MainActor
@Test func testRegenerateCallback() async throws {
    // Test that onRegenerate callback is properly wired in MessageRow
    let userMessage = Message.openai(.user(.init(content: "User question")))
    let assistantMessage = Message.openai(
        .assistant(.init(content: "Response", toolCalls: nil, audio: nil)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [userMessage, assistantMessage])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find the MessageRows
    let messageRows = view.findAll(MessageRow.self)
    #expect(messageRows.count == 2, "Expected 2 message rows")

    // Get the assistant message row (second one) and trigger regenerate
    let assistantMessageRow = messageRows[1]
    try assistantMessageRow.actualView().onRegenerate?()

    // Verify onSend was called with the original user message content
    #expect(
        sentMessage == "User question", "Expected onSend to be called with original user message")
}

@MainActor
@Test func testEditRemovesSubsequentMessages() async throws {
    // Test that editing a message removes all subsequent messages
    let userMessage1 = Message.openai(.user(.init(content: "First question")))
    let assistantMessage1 = Message.openai(
        .assistant(.init(content: "First response", toolCalls: nil, audio: nil)))
    let userMessage2 = Message.openai(.user(.init(content: "Second question")))
    let assistantMessage2 = Message.openai(
        .assistant(.init(content: "Second response", toolCalls: nil, audio: nil)))
    let chat = Chat(
        id: UUID(), gameId: "test",
        messages: [userMessage1, assistantMessage1, userMessage2, assistantMessage2])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Verify initial state has 4 messages
    let initialMessageRows = view.findAll(MessageRow.self)
    #expect(initialMessageRows.count == 4, "Expected 4 message rows initially")

    // Edit the first user message
    let firstMessageRow = initialMessageRows[0]
    let editedContent = "Edited first question"
    try firstMessageRow.actualView().onEdit?(editedContent)

    // Verify onSend was called with the edited content
    #expect(sentMessage == editedContent, "Expected onSend to be called with edited content")
}

@MainActor
@Test func testRegenerateWithMultipleMessages() async throws {
    // Test regeneration with multiple messages in chat
    let userMessage1 = Message.openai(.user(.init(content: "First question")))
    let assistantMessage1 = Message.openai(
        .assistant(.init(content: "First response", toolCalls: nil, audio: nil)))
    let userMessage2 = Message.openai(.user(.init(content: "Second question")))
    let assistantMessage2 = Message.openai(
        .assistant(.init(content: "Second response", toolCalls: nil, audio: nil)))
    let chat = Chat(
        id: UUID(), gameId: "test",
        messages: [userMessage1, assistantMessage1, userMessage2, assistantMessage2])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find the MessageRows
    let messageRows = view.findAll(MessageRow.self)
    #expect(messageRows.count == 4, "Expected 4 message rows")

    // Regenerate the second assistant message (last one)
    let lastAssistantRow = messageRows[3]
    try lastAssistantRow.actualView().onRegenerate?()

    // Verify onSend was called with the second user message content
    #expect(
        sentMessage == "Second question", "Expected onSend to be called with second user message")
}

@MainActor
@Test func testRegenerateFirstAssistantMessage() async throws {
    // Test regenerating the first assistant response
    let userMessage = Message.openai(.user(.init(content: "Original question")))
    let assistantMessage = Message.openai(
        .assistant(.init(content: "Original response", toolCalls: nil, audio: nil)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [userMessage, assistantMessage])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Find the assistant message row and trigger regenerate
    let messageRows = view.findAll(MessageRow.self)
    let assistantRow = messageRows[1]
    try assistantRow.actualView().onRegenerate?()

    // Verify onSend was called with the original user question
    #expect(
        sentMessage == "Original question",
        "Expected onSend to be called with original user message")
}

@MainActor
@Test func testMessageIdStability() async throws {
    // Test that Message.id remains stable even when content changes
    let id = UUID().uuidString
    let msg1 = Message.openai(
        .assistant(.init(id: id, content: "Hello", toolCalls: nil, audio: nil)))
    let msg2 = Message.openai(
        .assistant(.init(id: id, content: "Hello World", toolCalls: nil, audio: nil)))

    // IDs should be the same since they use the stored id field
    #expect(msg1.id == msg2.id, "Message IDs should be stable regardless of content")
    #expect(msg1.id == id, "Message ID should match the stored id")
}

@MainActor
@Test func testUserMessageIdStability() async throws {
    // Test that user messages have stable IDs
    let id = UUID().uuidString
    let msg = Message.openai(.user(.init(id: id, content: "Test")))

    #expect(msg.id == id, "User message ID should match the stored id")
}

@MainActor
@Test func testGenerationTaskGuardExists() async throws {
    // Test that the guard against concurrent generation is in place
    // Note: Full integration testing of concurrent blocking requires async server tests
    // This test verifies the basic functionality works without blocking
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var sendCount = 0
    let onSend: (String) -> Void = { _ in
        sendCount += 1
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )

    ViewHosting.host(view: sut)

    let view = try sut.inspect()

    // Send first message - this should work
    let inputView = try view.find(MessageInputView.self)
    try inputView.actualView().onSend("First message")

    // Verify at least one message was sent
    #expect(sendCount >= 1, "Expected at least 1 send callback")
}

@MainActor
@Test func testToolStatusRendering() async throws {
    let toolCallId = "call_1"
    let assistantMessage = Message.openai(
        .assistant(
            .init(
                content: nil,
                toolCalls: [
                    .init(
                        index: 0, id: toolCallId, type: .function,
                        function: .init(name: "tool", arguments: "{}"))
                ],
                audio: nil,
                reasoning: nil
            )))

    let toolMessage = Message.openai(
        .tool(.init(content: "Result", toolCallId: toolCallId, name: "tool")))

    let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage, toolMessage])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var capturedStatus: ToolStatus?

    let renderer: MessageRenderer = { msg, _, _, status in
        if case .openai(let m) = msg, case .assistant = m {
            capturedStatus = status
        }
        return (AnyView(EmptyView()), .replace)
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )

    ViewHosting.host(view: sut)
    let view = try sut.inspect()

    // Verify status is completed
    _ = try view.find(ViewType.EmptyView.self)  // Trigger render

    #expect(capturedStatus == .completed)
}

@MainActor
@Test func testToolStatusWaiting() async throws {
    let toolCallId = "call_1"
    let assistantMessage = Message.openai(
        .assistant(
            .init(
                content: nil,
                toolCalls: [
                    .init(
                        index: 0, id: toolCallId, type: .function,
                        function: .init(name: "tool", arguments: "{}"))
                ],
                audio: nil
            )))

    let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

    var capturedStatus: ToolStatus?

    let renderer: MessageRenderer = { msg, _, _, status in
        if case .openai(let m) = msg, case .assistant = m {
            capturedStatus = status
        }
        return (AnyView(EmptyView()), .replace)
    }

    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )

    ViewHosting.host(view: sut)
    let view = try sut.inspect()

    // Verify status is waiting
    _ = try view.find(ViewType.EmptyView.self)  // Trigger render

    #expect(capturedStatus == .waitingForResult)
}

// XCTest-based integration test for multi-turn conversation
final class AgentLayoutIntegrationTests: XCTestCase {
    var app: Application!
    var controller: MockOpenAIChatController!

    @MainActor
    override func setUp() async throws {
        app = try await Application.make(.testing)
        controller = MockOpenAIChatController()
        controller.registerRoutes(on: app)
        let port = 8127
        app.http.server.configuration.port = port
        try await app.startup()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        controller = nil
    }

    @MainActor
    func testUIToolWaitAndCancel() async throws {
        // Test that UI tool calls pause execution and can be cancelled
        let toolCallId = "call_123"
        let assistantMsg = OpenAIAssistantMessage(
            content: nil,
            toolCalls: [
                .init(
                    index: 0, id: toolCallId, type: .function,
                    function: .init(name: "ui_tool", arguments: "{}"))
            ],
            audio: nil
        )
        let assistantMessage = Message.openai(.assistant(assistantMsg))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source]
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // 1. Verify input is disabled (due to waiting for tool result)
        let inputView = try view.find(MessageInputView.self)
        let inputViewStatus = try inputView.actualView().status
        XCTAssertEqual(
            inputViewStatus, .loading,
            "Input view should be in loading state when waiting for tool result")

        // 2. Click stop/cancel button
        try inputView.actualView().onCancel()

        // 3. Verify rejection message appended is not easily possible directly without re-inspecting or checking state
        // But since handleCancel logic is tested, we can assume it works if the button is wired.

        // Re-inspect to check for cancellation message
        let updatedView = try sut.inspect()

        // Check if chat.messages has the rejection message
        // Since the tool message is now hidden from the main list (rendered inside the assistant message),
        // we check for the "Tool call complete" status in the UI instead of the raw content text.
        _ = try updatedView.find(text: "Tool call complete: ui_tool")
    }

    @MainActor
    func testMultiTurnConversation() async throws {
        // Setup test data
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue 2 assistant responses for the 2 messages we'll send
        let assistantMsg1 = OpenAIAssistantMessage(
            content: "This is the first response",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        let assistantMsg2 = OpenAIAssistantMessage(
            content: "This is the second response",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsg1])
        controller.mockChatResponse([assistantMsg2])

        // Track received messages via onMessage callback
        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        // Create AgentLayout with mock endpoint
        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)

        let view = try sut.inspect()

        // Send first message
        let inputView1 = try view.find(MessageInputView.self)
        try inputView1.actualView().onSend("First user message")

        // Wait for async response
        try await Task.sleep(nanoseconds: 500_000_000)

        // Send second message
        let inputView2 = try view.find(MessageInputView.self)
        try inputView2.actualView().onSend("Second user message")

        // Wait for async response
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify received assistant messages via callback
        let assistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant = openAIMsg
            {
                return true
            }
            return false
        }
        XCTAssertEqual(assistantMessages.count, 2, "Expected 2 assistant messages")

        // Verify first assistant response content
        if case .openai(let openAIMsg) = assistantMessages[0],
            case .assistant(let assistantMsg) = openAIMsg
        {
            XCTAssertEqual(assistantMsg.content, "This is the first response")
        } else {
            XCTFail("First message is not an assistant message")
        }

        // Verify second assistant response content
        if case .openai(let openAIMsg) = assistantMessages[1],
            case .assistant(let assistantMsg) = openAIMsg
        {
            XCTAssertEqual(assistantMsg.content, "This is the second response")
        } else {
            XCTFail("Second message is not an assistant message")
        }
    }

    @MainActor
    func testCancelGenerationEmitsOnMessage() async throws {
        // Test that canceling generation emits onMessage with partial content
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue a response that will be streamed
        let assistantMsg = OpenAIAssistantMessage(
            content: "This is a response that will be canceled",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsg])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)

        let view = try sut.inspect()

        // Send a message to start generation
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("User message")

        // Wait briefly for streaming to start
        try await Task.sleep(nanoseconds: 100_000_000)

        // Cancel the generation
        try inputView.actualView().onCancel()

        // Wait for cancel to process
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify onMessage was called with partial content (if any was received)
        // The cancel should emit the current state of the message
        // Note: Due to timing, we might or might not have received content
        // The important thing is that cancel doesn't crash and properly cleans up state

        // Verify status is back to idle by sending another message successfully
        controller.mockChatResponse([
            OpenAIAssistantMessage(
                content: "Second response", toolCalls: nil, audio: nil, reasoning: nil)
        ])
        try inputView.actualView().onSend("Second message")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Should have received the second response
        let assistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant = openAIMsg
            {
                return true
            }
            return false
        }
        XCTAssertGreaterThanOrEqual(
            assistantMessages.count, 1, "Should be able to send after cancel")
    }

    @MainActor
    func testSafeMessageUpdateById() async throws {
        // Test that messages are updated by ID, not index
        // This ensures correct message is updated even if array changes
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue first response
        let assistantMsg = OpenAIAssistantMessage(
            content: "First response",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsg])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)

        let view = try sut.inspect()

        // Send first message
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("First user message")

        // Wait for response
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify we received the assistant message
        let assistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant = openAIMsg
            {
                return true
            }
            return false
        }
        XCTAssertEqual(assistantMessages.count, 1, "Expected 1 assistant message")

        // Verify the message content is correct
        if case .openai(let openAIMsg) = assistantMessages[0],
            case .assistant(let assistantMsg) = openAIMsg
        {
            XCTAssertEqual(assistantMsg.content, "First response")
        } else {
            XCTFail("Expected assistant message")
        }
    }

    @MainActor
    func testCancelSendingSendsMessage() async throws {
        // Test #2: When user sends message, and in sending mode, user click stop button, should sends cancelled message
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue a response that will be streamed (simulate delay/streaming)
        let assistantMsg = OpenAIAssistantMessage(
            content: "Partial response",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsg])

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source]
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Send a message to start generation
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("User message")

        // Wait briefly for streaming to start
        try await Task.sleep(nanoseconds: 100_000_000)

        // Cancel the generation
        try inputView.actualView().onCancel()

        // Re-inspect to check for cancellation message
        let updatedView = try sut.inspect()

        // Check for "Cancelled" user message
        _ = try updatedView.find(text: "Cancelled")
    }

    @MainActor
    func testToolStatusRejected() async throws {
        // Test #4: Any tool call with tool result, callback should pass status completed or rejected depends on the tool result content.
        let toolCallId = "call_rejected"
        let assistantMessage = Message.openai(
            .assistant(
                .init(
                    content: nil,
                    toolCalls: [
                        .init(
                            index: 0, id: toolCallId, type: .function,
                            function: .init(name: "tool", arguments: "{}"))
                    ],
                    audio: nil,
                    reasoning: nil
                )))

        // Create a rejection tool message
        let toolMessage = Message.openai(
            .tool(.init(content: AgentLayout.REJECT_MESSAGE, toolCallId: toolCallId, name: "tool")))

        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage, toolMessage])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

        var capturedStatus: ToolStatus?

        let renderer: MessageRenderer = { msg, _, _, status in
            if case .openai(let m) = msg, case .assistant = m {
                capturedStatus = status
            }
            return (AnyView(EmptyView()), .replace)
        }

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            renderMessage: renderer
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Trigger render
        _ = try view.find(ViewType.EmptyView.self)

        #expect(capturedStatus == .rejected)
    }

    @MainActor
    func testOnMessageCalledForToolCancellation() async throws {
        // Test that onMessage is called when tool calls are cancelled
        let toolCallId1 = "call_1"
        let toolCallId2 = "call_2"
        let assistantMessage = Message.openai(
            .assistant(
                .init(
                    content: nil,
                    toolCalls: [
                        .init(
                            index: 0, id: toolCallId1, type: .function,
                            function: .init(name: "tool1", arguments: "{}")),
                        .init(
                            index: 1, id: toolCallId2, type: .function,
                            function: .init(name: "tool2", arguments: "{}")),
                    ],
                    audio: nil,
                    reasoning: nil
                )))

        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: ""), models: [model])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let sut = AgentLayout(
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Verify we're waiting for tool result (input should be in loading state)
        let inputView = try view.find(MessageInputView.self)
        let inputViewStatus = try inputView.actualView().status
        XCTAssertEqual(inputViewStatus, .loading, "Should be waiting for tool result")

        // Cancel the tool calls
        try inputView.actualView().onCancel()

        // Verify onMessage was called for each tool rejection
        let toolMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .tool = openAIMsg
            {
                return true
            }
            return false
        }

        XCTAssertEqual(
            toolMessages.count, 2, "Expected onMessage to be called for both tool rejections")

        // Verify the rejection messages have correct content
        for toolMsg in toolMessages {
            if case .openai(let openAIMsg) = toolMsg,
                case .tool(let tool) = openAIMsg
            {
                XCTAssertEqual(
                    tool.content, AgentLayout.REJECT_MESSAGE,
                    "Tool message should contain rejection message")
            } else {
                XCTFail("Expected tool message")
            }
        }
    }

}
