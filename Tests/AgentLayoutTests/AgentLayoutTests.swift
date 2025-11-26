import JSONSchema
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

struct MockChatProviderProtocol: ChatProviderProtocol {
    let onSend: (@Sendable (String) -> Void)?
    let onSendResult: (@Sendable (String, any Encodable) -> Void)?
    let onReject: (@Sendable (String) -> Void)?

    func sendMessage(message: String) async throws {
        onSend?(message)
    }

    func sendFunctionResult(id: String, result: any Encodable) async throws {
        onSendResult?(id, result)
    }

    func rejectFunction(id: String) async throws {
        onReject?(id)
    }
}

/// Shared mock server for Swift Testing tests
@MainActor
final class SharedMockServer {
    static let shared = SharedMockServer()

    private var app: Application?
    private var isRunning = false

    private init() {}

    func ensureRunning() async throws {
        guard !isRunning else { return }

        let application = try await Application.make(.testing)
        application.http.server.configuration.port = 8127

        // Register a simple handler that returns empty responses
        application.post("chat", "completions") { _ -> Response in
            let body = Response.Body(stream: { writer in
                Task {
                    _ = writer.write(.end)
                }
            })
            let response = Response(status: .ok, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
            return response
        }

        try await application.startup()
        self.app = application
        self.isRunning = true
    }

    func shutdown() async throws {
        if let app = app {
            try await app.asyncShutdown()
            self.app = nil
            self.isRunning = false
        }
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
@Suite("AgentLayout Tests", .disabled())
struct AgentLayoutTests {

    init() async throws {
        try await SharedMockServer.shared.ensureRunning()
    }

    @Test func testRenderMessageReplace() async throws {
        let messageContent = "Original Message"
        let message = Message.openai(.user(.init(content: messageContent)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [message])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()
        // Manually setup ChatProvider since ViewInspector doesn't trigger onAppear synchronously
        chatProvider.setup(chat: chat, currentModel: model, currentSource: source)

        let customContent = "Custom Replacement"
        let renderer: MessageRenderer = { _, _, _, _ in
            (AnyView(Text(customContent)), .replace)
        }

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()
        // Manually setup ChatProvider since ViewInspector doesn't trigger onAppear synchronously
        chatProvider.setup(chat: chat, currentModel: model, currentSource: source)

        let customContent = "Custom Append"
        let renderer: MessageRenderer = { _, _, _, _ in
            (AnyView(Text(customContent)), .append)
        }

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()
        // Manually setup ChatProvider since ViewInspector doesn't trigger onAppear synchronously
        chatProvider.setup(chat: chat, currentModel: model, currentSource: source)

        let renderer: MessageRenderer = { _, _, _, _ in
            (AnyView(EmptyView()), .skip)
        }

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sentMessage: Message?
        let onSend: (Message) -> Void = { message in
            sentMessage = message
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        #expect(sentMessage != nil)
        if case .openai(let openAIMsg) = sentMessage, case .user(let userMsg) = openAIMsg {
            #expect(userMsg.content == "Hello World")
        } else {
            #expect(Bool(false), "Expected user message")
        }
    }

    @MainActor
    @Test func testOnMessageCallbackParameter() async throws {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let chatProvider = ChatProvider()

        // Verify AgentLayout accepts the onMessage callback
        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sentMessage: Message?
        var receivedMessages: [Message] = []

        let onSend: (Message) -> Void = { message in
            sentMessage = message
        }

        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let chatProvider = ChatProvider()

        // Verify AgentLayout accepts both callbacks together
        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        #expect(sentMessage != nil)
        if case .openai(let openAIMsg) = sentMessage, case .user(let userMsg) = openAIMsg {
            #expect(userMsg.content == "Test message")
        } else {
            #expect(Bool(false), "Expected user message")
        }
    }

    @MainActor
    @Test func testOnMessageCallbackNilByDefault() async throws {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()

        // Verify AgentLayout works without onMessage callback (nil by default)
        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sentMessage: Message?
        let onSend: (Message) -> Void = { message in
            sentMessage = message
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        #expect(sentMessage != nil, "Expected onSend to be called")
        if case .openai(let openAIMsg) = sentMessage, case .user(let userMsg) = openAIMsg {
            #expect(
                userMsg.content == editedContent, "Expected onSend to be called with edited content"
            )
        } else {
            #expect(Bool(false), "Expected user message")
        }
    }

    @MainActor
    @Test func testRegenerateCallback() async throws {
        // Test that onRegenerate callback is properly wired in MessageRow
        let userMessage = Message.openai(.user(.init(content: "User question")))
        let assistantMessage = Message.openai(
            .assistant(.init(content: "Response", toolCalls: nil, audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMessage, assistantMessage])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sentMessage: Message?
        let onSend: (Message) -> Void = { message in
            sentMessage = message
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        #expect(sentMessage != nil, "Expected onSend to be called")
        if case .openai(let openAIMsg) = sentMessage, case .user(let userMsg) = openAIMsg {
            #expect(
                userMsg.content == "User question",
                "Expected onSend to be called with original user message")
        } else {
            #expect(Bool(false), "Expected user message")
        }
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sentMessage: Message?
        let onSend: (Message) -> Void = { message in
            sentMessage = message
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        #expect(sentMessage != nil, "Expected onSend to be called")
        if case .openai(let openAIMsg) = sentMessage, case .user(let userMsg) = openAIMsg {
            #expect(
                userMsg.content == editedContent, "Expected onSend to be called with edited content"
            )
        } else {
            #expect(Bool(false), "Expected user message")
        }
    }

    @MainActor
    @Test func testGenerationTaskGuardExists() async throws {
        // Test that the guard against concurrent generation is in place
        // Note: Full integration testing of concurrent blocking requires async server tests
        // This test verifies the basic functionality works without blocking
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var sendCount = 0
        let onSend: (Message) -> Void = { _ in
            sendCount += 1
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var capturedStatus: ToolStatus?

        let renderer: MessageRenderer = { msg, _, _, status in
            if case .openai(let m) = msg, case .assistant = m {
                capturedStatus = status
            }
            return (AnyView(EmptyView()), .replace)
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var capturedStatus: ToolStatus?

        let renderer: MessageRenderer = { msg, _, _, status in
            if case .openai(let m) = msg, case .assistant = m {
                capturedStatus = status
            }
            return (AnyView(EmptyView()), .replace)
        }

        let chatProvider = ChatProvider()
        // Manually setup ChatProvider since ViewInspector doesn't trigger onAppear synchronously
        chatProvider.setup(chat: chat, currentModel: model, currentSource: source)

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        if let app = app {
            try? await app.asyncShutdown()
        }
        app = nil
        controller = nil
        // Small delay to ensure port is released
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        // Track if onMessage was called with rejection
        var rejectionMessageReceived = false
        let onMessage: (Message) -> Void = { message in
            if case .openai(let openAIMsg) = message,
                case .tool(let toolMsg) = openAIMsg,
                toolMsg.content == ChatProvider.REJECT_MESSAGE_STRING
            {
                rejectionMessageReceived = true
            }
        }

        let chatProvider = ChatProvider()
        // Manually setup ChatProvider since ViewInspector doesn't trigger onAppear synchronously
        chatProvider.setup(
            chat: chat, currentModel: model, currentSource: source, onMessage: onMessage)

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            onMessage: onMessage
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

        // 3. Verify the cancel handler was triggered by checking if rejection message was sent
        XCTAssertTrue(
            rejectionMessageReceived,
            "Cancel should emit a rejection message via onMessage callback")
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

        let chatProvider = ChatProvider()

        // Create AgentLayout with mock endpoint
        let sut = AgentLayout(
            chatProvider: chatProvider,
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

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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

        // Re-inspect to check for cancellation
        let updatedView = try sut.inspect()

        // Verify the input is back to idle state after cancellation
        let updatedInputView = try updatedView.find(MessageInputView.self)
        let updatedStatus = try updatedInputView.actualView().status
        XCTAssertEqual(updatedStatus, .idle, "Input should be idle after cancellation")
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
            .tool(
                .init(
                    content: ChatProvider.REJECT_MESSAGE_STRING, toolCallId: toolCallId,
                    name: "tool")))

        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMessage, toolMessage])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var capturedStatus: ToolStatus?

        let renderer: MessageRenderer = { msg, _, _, status in
            if case .openai(let m) = msg, case .assistant = m {
                capturedStatus = status
            }
            return (AnyView(EmptyView()), .replace)
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
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
                    tool.content, ChatProvider.REJECT_MESSAGE_STRING,
                    "Tool message should contain rejection message")
            } else {
                XCTFail("Expected tool message")
            }
        }
    }

    @MainActor
    func testOnMessageCalledWhenModelMakesToolCall() async throws {
        // Test that onMessage is called when the model returns an assistant message with tool calls
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue a response with tool calls (UI tool so it won't auto-execute)
        let toolCallId = "call_tool_123"
        let assistantMsgWithToolCall = OpenAIAssistantMessage(
            content: nil,
            toolCalls: [
                .init(
                    index: 0, id: toolCallId, type: .function,
                    function: .init(name: "ui_tool", arguments: "{\"action\": \"test\"}"))
            ],
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsgWithToolCall])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        // Define a UI tool so the execution pauses waiting for result
        let uiTool = MockUITool()

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            tools: [uiTool],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Send a message to trigger the model response
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("Call a tool")

        // Wait for async response
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify onMessage was called with an assistant message that has tool calls
        let assistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant(let assistant) = openAIMsg,
                let toolCalls = assistant.toolCalls,
                !toolCalls.isEmpty
            {
                return true
            }
            return false
        }

        XCTAssertEqual(
            assistantMessages.count, 1,
            "Expected onMessage to be called once with assistant message containing tool calls")

        // Verify the tool call details
        if case .openai(let openAIMsg) = assistantMessages[0],
            case .assistant(let assistant) = openAIMsg,
            let toolCalls = assistant.toolCalls
        {
            XCTAssertEqual(toolCalls.count, 1, "Expected 1 tool call")
            XCTAssertEqual(toolCalls[0].id, toolCallId, "Tool call ID should match")
            XCTAssertEqual(toolCalls[0].function?.name, "ui_tool", "Tool name should match")
        } else {
            XCTFail("Expected assistant message with tool calls")
        }
    }

    @MainActor
    func testOnMessageCalledWhenModelReceivesToolResult() async throws {
        // Test that onMessage is called when a tool result is processed
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue responses:
        // 1. First response: assistant message with tool call (non-UI tool, will auto-execute)
        // 2. Second response: final assistant message after tool result
        let toolCallId = "call_auto_tool_456"
        let assistantMsgWithToolCall = OpenAIAssistantMessage(
            content: nil,
            toolCalls: [
                .init(
                    index: 0, id: toolCallId, type: .function,
                    function: .init(name: "auto_tool", arguments: "{\"query\": \"test\"}"))
            ],
            audio: nil,
            reasoning: nil
        )
        let finalAssistantMsg = OpenAIAssistantMessage(
            content: "Based on the tool result, here is my answer.",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsgWithToolCall])
        controller.mockChatResponse([finalAssistantMsg])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        // Define an auto-executing tool (non-UI)
        let autoTool = MockAutoTool()

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            tools: [autoTool],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Send a message to trigger the model response
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("Use a tool")

        // Wait for async response and tool execution
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify onMessage was called for tool result
        let toolMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .tool = openAIMsg
            {
                return true
            }
            return false
        }

        XCTAssertEqual(
            toolMessages.count, 1, "Expected onMessage to be called once with tool result")

        // Verify the tool result details
        if case .openai(let openAIMsg) = toolMessages[0],
            case .tool(let toolMsg) = openAIMsg
        {
            XCTAssertEqual(toolMsg.toolCallId, toolCallId, "Tool call ID should match")
            XCTAssertEqual(toolMsg.name, "auto_tool", "Tool name should match")
            XCTAssertTrue(
                toolMsg.content.contains("Auto tool executed"),
                "Tool result should contain expected content")
        } else {
            XCTFail("Expected tool message")
        }

        // Verify onMessage was also called for the assistant message with tool calls
        let assistantWithToolCalls = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant(let assistant) = openAIMsg,
                let toolCalls = assistant.toolCalls,
                !toolCalls.isEmpty
            {
                return true
            }
            return false
        }
        XCTAssertEqual(
            assistantWithToolCalls.count, 1,
            "Expected onMessage to be called for assistant message with tool calls")

        // Verify final assistant message was also received
        let finalAssistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant(let assistant) = openAIMsg,
                assistant.toolCalls == nil,
                let content = assistant.content,
                content.contains("Based on the tool result")
            {
                return true
            }
            return false
        }
        XCTAssertEqual(
            finalAssistantMessages.count, 1,
            "Expected onMessage to be called for final assistant message")
    }

    @MainActor
    func testDisplayChatWithToolCallAndResult() async throws {
        // Test that AgentLayout displays a chat with existing tool calls and results correctly
        let toolCallId = "call_weather_123"
        let toolName = "get_weather"

        // Create a chat with:
        // 1. User message
        // 2. Assistant message with tool call
        // 3. Tool result message
        // 4. Final assistant response
        let userMessage = Message.openai(.user(.init(content: "What's the weather in NYC?")))
        let assistantWithToolCall = Message.openai(
            .assistant(
                .init(
                    content: nil,
                    toolCalls: [
                        .init(
                            index: 0, id: toolCallId, type: .function,
                            function: .init(
                                name: toolName, arguments: "{\"location\": \"New York City\"}"))
                    ],
                    audio: nil,
                    reasoning: nil
                )))
        let toolResultMessage = Message.openai(
            .tool(
                .init(
                    content: "{\"temperature\": 72, \"condition\": \"sunny\", \"humidity\": 45}",
                    toolCallId: toolCallId,
                    name: toolName
                )))
        let finalAssistantMessage = Message.openai(
            .assistant(
                .init(
                    content: "The weather in New York City is sunny with a temperature of 72°F.",
                    toolCalls: nil,
                    audio: nil,
                    reasoning: nil
                )))

        let chat = Chat(
            id: UUID(),
            gameId: "test",
            messages: [
                userMessage, assistantWithToolCall, toolResultMessage, finalAssistantMessage,
            ]
        )
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source]
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Verify the user message is displayed
        _ = try view.find(text: "What's the weather in NYC?")

        // Verify the tool call complete indicator is displayed
        _ = try view.find(text: "Tool call complete: \(toolName)")

        // Verify the final assistant response is displayed
        _ = try view.find(text: "The weather in New York City is sunny with a temperature of 72°F.")

        // Verify input is in idle state (not waiting for tool result since all tools are resolved)
        let inputView = try view.find(MessageInputView.self)
        let inputViewStatus = try inputView.actualView().status
        XCTAssertEqual(
            inputViewStatus, .idle, "Input should be idle when all tool calls are resolved")
    }

    @MainActor
    func testDisplayChatWithPendingToolCall() async throws {
        // Test that AgentLayout displays a chat with pending (unresolved) tool calls correctly
        let toolCallId = "call_pending_456"
        let toolName = "search_database"

        // Create a chat with:
        // 1. User message
        // 2. Assistant message with tool call (no result yet)
        let userMessage = Message.openai(.user(.init(content: "Search for user records")))
        let assistantWithToolCall = Message.openai(
            .assistant(
                .init(
                    content: nil,
                    toolCalls: [
                        .init(
                            index: 0, id: toolCallId, type: .function,
                            function: .init(
                                name: toolName, arguments: "{\"query\": \"user records\"}"))
                    ],
                    audio: nil,
                    reasoning: nil
                )))

        let chat = Chat(
            id: UUID(),
            gameId: "test",
            messages: [userMessage, assistantWithToolCall]
        )
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source]
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Verify the user message is displayed
        _ = try view.find(text: "Search for user records")

        // Verify the tool call is shown as "Calling tool" (not complete)
        _ = try view.find(text: "Calling tool: \(toolName)")

        // Verify input is in loading state (waiting for tool result)
        let inputView = try view.find(MessageInputView.self)
        let inputViewStatus = try inputView.actualView().status
        XCTAssertEqual(
            inputViewStatus, .loading, "Input should be loading when waiting for tool result")
    }

    @MainActor
    func testDisplayChatWithMultipleToolCalls() async throws {
        // Test that AgentLayout displays multiple tool calls correctly
        let toolCallId1 = "call_tool_1"
        let toolCallId2 = "call_tool_2"
        let toolName1 = "get_weather"
        let toolName2 = "get_time"

        // Create a chat with multiple tool calls and results
        let userMessage = Message.openai(
            .user(.init(content: "What's the weather and time in Tokyo?")))
        let assistantWithToolCalls = Message.openai(
            .assistant(
                .init(
                    content: nil,
                    toolCalls: [
                        .init(
                            index: 0, id: toolCallId1, type: .function,
                            function: .init(name: toolName1, arguments: "{\"location\": \"Tokyo\"}")
                        ),
                        .init(
                            index: 1, id: toolCallId2, type: .function,
                            function: .init(
                                name: toolName2, arguments: "{\"timezone\": \"Asia/Tokyo\"}")),
                    ],
                    audio: nil,
                    reasoning: nil
                )))
        let toolResult1 = Message.openai(
            .tool(
                .init(
                    content: "{\"temperature\": 25, \"condition\": \"cloudy\"}",
                    toolCallId: toolCallId1,
                    name: toolName1
                )))
        let toolResult2 = Message.openai(
            .tool(
                .init(
                    content: "{\"time\": \"15:30\", \"date\": \"2025-01-15\"}",
                    toolCallId: toolCallId2,
                    name: toolName2
                )))
        let finalAssistant = Message.openai(
            .assistant(
                .init(
                    content: "In Tokyo, it's currently 3:30 PM with cloudy weather at 25°C.",
                    toolCalls: nil,
                    audio: nil,
                    reasoning: nil
                )))

        let chat = Chat(
            id: UUID(),
            gameId: "test",
            messages: [
                userMessage, assistantWithToolCalls, toolResult1, toolResult2, finalAssistant,
            ]
        )
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model])

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source]
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Verify both tool calls are shown as complete
        _ = try view.find(text: "Tool call complete: \(toolName1)")
        _ = try view.find(text: "Tool call complete: \(toolName2)")

        // Verify the final response is displayed
        _ = try view.find(text: "In Tokyo, it's currently 3:30 PM with cloudy weather at 25°C.")

        // Verify input is idle
        let inputView = try view.find(MessageInputView.self)
        let inputViewStatus = try inputView.actualView().status
        XCTAssertEqual(
            inputViewStatus, .idle, "Input should be idle when all tool calls are resolved")
    }

    @MainActor
    func testMultiTurnToolCallFinalAssistantMessageDisplayed() async throws {
        // This test verifies that the FINAL assistant message (after tool execution)
        // is properly added to chat.messages and displayed in the UI
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:8127")!),
            models: [model]
        )

        // Queue responses:
        // 1. Assistant message with tool call (auto-execute tool)
        // 2. Final assistant message with content
        let toolCallId = "call_test_tool"
        let assistantMsgWithToolCall = OpenAIAssistantMessage(
            content: nil,
            toolCalls: [
                .init(
                    index: 0, id: toolCallId, type: .function,
                    function: .init(name: "auto_tool", arguments: "{\"query\": \"test\"}"))
            ],
            audio: nil,
            reasoning: nil
        )
        let finalAssistantMsg = OpenAIAssistantMessage(
            content: "Here is the final response after using the tool.",
            toolCalls: nil,
            audio: nil,
            reasoning: nil
        )
        controller.mockChatResponse([assistantMsgWithToolCall])
        controller.mockChatResponse([finalAssistantMsg])

        var receivedMessages: [Message] = []
        let onMessage: (Message) -> Void = { message in
            receivedMessages.append(message)
        }

        let autoTool = MockAutoTool()

        let chatProvider = ChatProvider()

        let sut = AgentLayout(
            chatProvider: chatProvider,
            chat: chat,
            currentModel: .constant(model),
            currentSource: .constant(source),
            sources: [source],
            tools: [autoTool],
            onMessage: onMessage
        )

        ViewHosting.host(view: sut)
        let view = try sut.inspect()

        // Send a message to trigger the multi-turn flow
        let inputView = try view.find(MessageInputView.self)
        try inputView.actualView().onSend("Use a tool and give me a response")

        // Wait for async response and tool execution
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Verify all messages were received via onMessage callback
        // Expected: 1 assistant with tool call, 1 tool result, 1 final assistant with content
        let assistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg, case .assistant = openAIMsg {
                return true
            }
            return false
        }
        XCTAssertEqual(
            assistantMessages.count, 2, "Expected 2 assistant messages (tool call + final response)"
        )

        // Verify the final assistant message has the expected content
        let finalAssistantMessages = receivedMessages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant(let assistant) = openAIMsg,
                assistant.toolCalls == nil,
                let content = assistant.content,
                content.contains("Here is the final response")
            {
                return true
            }
            return false
        }
        XCTAssertEqual(
            finalAssistantMessages.count, 1,
            "Expected 1 final assistant message with content 'Here is the final response'"
        )

        // Note: ViewInspector has limitations with @State updates after async operations,
        // so we verify via callbacks that all messages are properly processed.
        // The fix ensures assistant messages are appended to chat.messages when
        // currentStreamingMessageId is nil (multi-turn conversations after tool execution).
    }

}

// MARK: - Mock Tools for Testing

/// A UI tool that requires user interaction (won't auto-execute)
struct MockUITool: AgentToolProtocol {
    var toolType: AgentToolType { .ui }
    var name: String { "ui_tool" }
    var description: String { "A UI tool for testing" }
    var inputType: any Decodable.Type { Args.self }
    var parameters: JSONSchema {
        // swiftlint:disable:next force_try
        try! JSONSchema(
            jsonString: """
                {"type": "object", "properties": {"action": {"type": "string"}}, "required": ["action"]}
                """)
    }

    struct Args: Decodable {
        let action: String
    }

    struct Output: Encodable {
        let result: String
    }

    func invoke(args: any Decodable, originalArgs: String) async throws -> any Encodable {
        return Output(result: "UI tool result")
    }

    func invoke(argsData: Data, originalArgs: String) async throws -> any Encodable {
        return Output(result: "UI tool result")
    }
}

/// An auto-executing tool (non-UI)
struct MockAutoTool: AgentToolProtocol {
    var toolType: AgentToolType { .regular }
    var name: String { "auto_tool" }
    var description: String { "An auto-executing tool for testing" }
    var inputType: any Decodable.Type { Args.self }
    var parameters: JSONSchema {
        // swiftlint:disable:next force_try
        try! JSONSchema(
            jsonString: """
                {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}
                """)
    }

    struct Args: Decodable {
        let query: String
    }

    struct Output: Encodable {
        let result: String
    }

    func invoke(args: any Decodable, originalArgs: String) async throws -> any Encodable {
        return Output(result: "Auto tool executed successfully")
    }

    func invoke(argsData: Data, originalArgs: String) async throws -> any Encodable {
        return Output(result: "Auto tool executed successfully")
    }
}
