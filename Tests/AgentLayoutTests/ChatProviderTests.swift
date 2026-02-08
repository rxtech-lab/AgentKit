import SwiftUI
import Testing

@testable import Agent
@testable import AgentLayout

// MARK: - ChatProvider Unit Tests

@MainActor
@Suite("ChatProvider Tests")
struct ChatProviderTests {

    // MARK: - Initialization Tests

    @Test("ChatProvider initializes with empty constructor")
    func testInit() {
        let provider = ChatProvider()

        #expect(provider.chat == nil)
        #expect(provider.currentModel == nil)
        #expect(provider.currentSource == nil)
        #expect(provider.status == .idle)
        #expect(provider.messages.isEmpty)
        #expect(provider.systemPrompt == nil)
        #expect(provider.tools.isEmpty)
    }

    @Test("ChatProvider setup sets correct values")
    func testSetup() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.chat?.id == chat.id)
        #expect(provider.currentModel?.id == model.id)
        #expect(provider.currentSource?.id == source.id)
        #expect(provider.status == .idle)
        #expect(provider.messages.isEmpty)
        #expect(provider.systemPrompt == nil)
        #expect(provider.tools.isEmpty)
    }

    @Test("ChatProvider setup with system prompt")
    func testSetupWithSystemPrompt() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])
        let systemPrompt = "You are a helpful assistant"

        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            systemPrompt: systemPrompt
        )

        #expect(provider.systemPrompt == systemPrompt)
    }

    @Test("ChatProvider setup with callbacks")
    func testSetupWithCallbacks() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var onSendCalled = false
        var onMessageCalled = false
        var onDeleteCalled = false
        var onEditCalled = false

        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onSend: { _ in onSendCalled = true },
            onMessage: { _ in onMessageCalled = true },
            onDelete: { _ in onDeleteCalled = true },
            onEdit: { _, _ in onEditCalled = true }
        )

        // Verify callbacks are set (we'll test invocation separately)
        #expect(provider.onSend != nil)
        #expect(provider.onMessage != nil)
        #expect(provider.onDelete != nil)
        #expect(provider.onEdit != nil)
    }

    @Test("ChatProvider setup only runs once for same chat ID")
    func testSetupOnlyRunsOnceForSameChatId() {
        let chatId = UUID()
        let chat1 = Chat(id: chatId, gameId: "test1", messages: [])
        let chat2 = Chat(id: chatId, gameId: "test2", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat1, currentModel: model, currentSource: source)
        provider.setup(chat: chat2, currentModel: model, currentSource: source)

        // Should still have chat1 since setup only fully runs once for the same chat ID
        #expect(provider.chat?.gameId == "test1")
    }

    @Test("ChatProvider setup re-runs for different chat ID")
    func testSetupRerunsForDifferentChatId() {
        let chat1 = Chat(id: UUID(), gameId: "test1", messages: [])
        let chat2 = Chat(id: UUID(), gameId: "test2", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat1, currentModel: model, currentSource: source)
        provider.setup(chat: chat2, currentModel: model, currentSource: source)

        // Should have chat2 since setup re-runs for different chat ID
        #expect(provider.chat?.gameId == "test2")
    }

    // MARK: - Messages Property Tests

    @Test("messages property returns chat messages")
    func testMessagesProperty() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let assistantMsg = Message.openai(.assistant(.init(content: "Hi there!", audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg, assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(provider.messages.count == 2)
        #expect(provider.messages[0].id == userMsg.id)
        #expect(provider.messages[1].id == assistantMsg.id)
    }

    // MARK: - isWaitingForToolResult Tests

    @Test("isWaitingForToolResult returns false when no tool calls")
    func testIsWaitingForToolResultNoToolCalls() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(!provider.isWaitingForToolResult)
    }

    @Test("isWaitingForToolResult returns true when tool call has no result")
    func testIsWaitingForToolResultWithPendingToolCall() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(provider.isWaitingForToolResult)
    }

    @Test("isWaitingForToolResult returns false when tool call has result")
    func testIsWaitingForToolResultWithResolvedToolCall() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let toolResult = Message.openai(.tool(.init(content: "Result", toolCallId: toolCallId)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg, toolResult])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(!provider.isWaitingForToolResult)
    }

    @Test("isWaitingForToolResult returns true when only some tool calls resolved")
    func testIsWaitingForToolResultPartiallyResolved() {
        let toolCallId1 = "call_1"
        let toolCallId2 = "call_2"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId1, type: .function, function: .init(name: "tool1", arguments: "{}")),
                .init(index: 1, id: toolCallId2, type: .function, function: .init(name: "tool2", arguments: "{}"))
            ],
            audio: nil
        )))
        let toolResult1 = Message.openai(.tool(.init(content: "Result1", toolCallId: toolCallId1)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg, toolResult1])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(provider.isWaitingForToolResult)
    }

    // MARK: - getToolStatus Tests

    @Test("getToolStatus returns completed for message without tool calls")
    func testGetToolStatusNoToolCalls() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        let status = provider.getToolStatus(for: userMsg, in: chat.messages)
        #expect(status == .completed)
    }

    @Test("getToolStatus returns waitingForResult for pending tool call")
    func testGetToolStatusWaiting() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        let status = provider.getToolStatus(for: assistantMsg, in: chat.messages)
        #expect(status == .waitingForResult)
    }

    @Test("getToolStatus returns completed for resolved tool call")
    func testGetToolStatusCompleted() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let toolResult = Message.openai(.tool(.init(content: "Result", toolCallId: toolCallId)))
        let messages = [assistantMsg, toolResult]
        let chat = Chat(id: UUID(), gameId: "test", messages: messages)
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        let status = provider.getToolStatus(for: assistantMsg, in: messages)
        #expect(status == .completed)
    }

    @Test("getToolStatus returns rejected for rejected tool call")
    func testGetToolStatusRejected() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let toolResult = Message.openai(.tool(.init(content: ChatProvider.REJECT_MESSAGE_STRING, toolCallId: toolCallId)))
        let messages = [assistantMsg, toolResult]
        let chat = Chat(id: UUID(), gameId: "test", messages: messages)
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        let status = provider.getToolStatus(for: assistantMsg, in: messages)
        #expect(status == .rejected)
    }

    // MARK: - deleteMessage Tests

    @Test("deleteMessage removes message and calls callback")
    func testDeleteMessage() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let assistantMsg = Message.openai(.assistant(.init(content: "Hi!", audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg, assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var deletedIndex: Int?
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onDelete: { index in deletedIndex = index }
        )

        provider.deleteMessage(at: 0)

        #expect(provider.messages.count == 1)
        #expect(provider.messages[0].id == assistantMsg.id)
        #expect(deletedIndex == 0)
    }

    // MARK: - updateChat Tests

    @Test("updateChat replaces chat")
    func testUpdateChat() {
        let chat1 = Chat(id: UUID(), gameId: "test1", messages: [])
        let chat2 = Chat(id: UUID(), gameId: "test2", messages: [
            Message.openai(.user(.init(content: "New message")))
        ])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat1, currentModel: model, currentSource: source)

        provider.updateChat(chat2)

        #expect(provider.chat?.id == chat2.id)
        #expect(provider.chat?.gameId == "test2")
        #expect(provider.messages.count == 1)
    }

    // MARK: - Constants Tests

    @Test("REJECT_MESSAGE_STRING has expected value")
    func testRejectMessageString() {
        #expect(ChatProvider.REJECT_MESSAGE_STRING == "User cancelled this tool call")
    }

    // MARK: - Model/Source Update Tests

    @Test("currentModel can be updated")
    func testCurrentModelUpdate() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model1 = Model.openAI(.init(id: "gpt-4"))
        let model2 = Model.openAI(.init(id: "gpt-3.5-turbo"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model1, model2])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model1, currentSource: source)

        provider.currentModel = model2
        #expect(provider.currentModel?.id == model2.id)
    }

    @Test("currentSource can be updated")
    func testCurrentSourceUpdate() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source1 = Source.openAI(client: OpenAIClient(apiKey: "key1"), models: [model])
        let source2 = Source.openAI(client: OpenAIClient(apiKey: "key2"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source1)

        provider.currentSource = source2
        #expect(provider.currentSource?.id == source2.id)
    }

    // MARK: - Cancel with Pending Tool Calls Tests

    // MARK: - updateTools Tests

    @Test("updateTools replaces tools array")
    func testUpdateTools() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(provider.tools.isEmpty)

        let mockTool = MockTestTool()
        provider.updateTools([mockTool])

        #expect(provider.tools.count == 1)
        #expect(provider.tools[0].name == "test_tool")
    }

    @Test("updateTools can clear tools")
    func testUpdateToolsClear() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let mockTool = MockTestTool()
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source, tools: [mockTool])

        #expect(provider.tools.count == 1)

        provider.updateTools([])

        #expect(provider.tools.isEmpty)
    }

    // MARK: - updateSystemPrompt Tests

    @Test("updateSystemPrompt sets new prompt")
    func testUpdateSystemPrompt() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)

        #expect(provider.systemPrompt == nil)

        provider.updateSystemPrompt("You are a helpful assistant")

        #expect(provider.systemPrompt == "You are a helpful assistant")
    }

    @Test("updateSystemPrompt can clear prompt")
    func testUpdateSystemPromptClear() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source, systemPrompt: "Initial prompt")

        #expect(provider.systemPrompt == "Initial prompt")

        provider.updateSystemPrompt(nil)

        #expect(provider.systemPrompt == nil)
    }

    // MARK: - sendMessage Tests

    @Test("sendMessage base implementation does not throw")
    func testSendMessageBaseImplementation() async throws {
        let provider = ChatProvider()

        // Should not throw - base implementation is empty
        try await provider.sendMessage(message: "test message")
    }

    // MARK: - Cancel with Pending Tool Calls Tests

    @Test("cancel rejects all pending tool calls")
    func testCancelRejectsPendingToolCalls() {
        let toolCallId1 = "call_1"
        let toolCallId2 = "call_2"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId1, type: .function, function: .init(name: "tool1", arguments: "{}")),
                .init(index: 1, id: toolCallId2, type: .function, function: .init(name: "tool2", arguments: "{}"))
            ],
            audio: nil
        )))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var receivedMessages: [Message] = []
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessage: { msg in receivedMessages.append(msg) }
        )

        // Verify we're waiting for tool result before cancel
        #expect(provider.isWaitingForToolResult)

        provider.cancel()

        // Verify tool rejections were added
        #expect(provider.messages.count == 3)

        // Verify onMessage was called for each rejection
        #expect(receivedMessages.count == 2)

        // Verify rejection content
        for msg in receivedMessages {
            if case .openai(let openAIMsg, _) = msg, case .tool(let toolMsg) = openAIMsg {
                #expect(toolMsg.content == ChatProvider.REJECT_MESSAGE_STRING)
            } else {
                Issue.record("Expected tool message")
            }
        }

        // Verify no longer waiting for tool result
        #expect(!provider.isWaitingForToolResult)
    }

    // MARK: - onMessageChange Tests

    @Test("onMessageChange callback is set during setup")
    func testOnMessageChangeSetup() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var receivedMessages: [[Message]] = []
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { messages in receivedMessages.append(messages) }
        )

        #expect(provider.onMessageChange != nil)
    }

    @Test("onMessageChange is NOT called during initial setup")
    func testOnMessageChangeNotCalledOnSetup() {
        let existingMsg = Message.openai(.user(.init(content: "Existing")))
        let chat = Chat(id: UUID(), gameId: "test", messages: [existingMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var callCount = 0
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { _ in callCount += 1 }
        )

        #expect(callCount == 0)
    }

    @Test("onMessageChange is called when message is deleted")
    func testOnMessageChangeOnDelete() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let assistantMsg = Message.openai(.assistant(.init(content: "Hi!", audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg, assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var receivedMessages: [[Message]] = []
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { messages in receivedMessages.append(messages) }
        )

        provider.deleteMessage(at: 0)

        #expect(receivedMessages.count == 1)
        #expect(receivedMessages[0].count == 1)
        #expect(receivedMessages[0][0].id == assistantMsg.id)
    }

    @Test("onMessageChange receives full message array")
    func testOnMessageChangeReceivesFullArray() {
        let userMsg = Message.openai(.user(.init(content: "Hello")))
        let chat = Chat(id: UUID(), gameId: "test", messages: [userMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var receivedMessages: [[Message]] = []
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { messages in receivedMessages.append(messages) }
        )

        // Delete the only message
        provider.deleteMessage(at: 0)

        #expect(receivedMessages.count == 1)
        #expect(receivedMessages[0].isEmpty)  // Should receive empty array
    }

    @Test("onMessageChange is called when cancel adds rejection messages")
    func testOnMessageChangeOnCancelWithToolCalls() {
        let toolCallId = "call_123"
        let assistantMsg = Message.openai(.assistant(.init(
            content: nil,
            toolCalls: [
                .init(index: 0, id: toolCallId, type: .function, function: .init(name: "test_tool", arguments: "{}"))
            ],
            audio: nil
        )))
        let chat = Chat(id: UUID(), gameId: "test", messages: [assistantMsg])
        let model = Model.openAI(.init(id: "gpt-4"))
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [model])

        var callCount = 0
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { _ in callCount += 1 }
        )

        provider.cancel()

        #expect(callCount >= 1)  // At least one call when rejection message is added
    }
    
    // MARK: - Custom Agent Tests
    
    @Test("onCustomAgentSend callback is set during setup")
    func testOnCustomAgentSendSetup() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        var callbackCalled = false
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onCustomAgentSend: { _, _ in callbackCalled = true }
        )
        
        #expect(provider.onCustomAgentSend != nil)
    }
    
    @Test("updateMessages replaces all messages")
    func testUpdateMessages() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [
            .openai(.user(.init(content: "Original")))
        ])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)
        
        let newMessages = [
            Message.openai(.user(.init(content: "New message 1"))),
            Message.openai(.assistant(.init(content: "New response", toolCalls: nil, audio: nil)))
        ]
        provider.updateMessages(newMessages)
        
        #expect(provider.messages.count == 2)
        if case .openai(let msg, _) = provider.messages[0], case .user(let user) = msg {
            #expect(user.content == "New message 1")
        }
    }
    
    @Test("updateMessages calls onMessageChange")
    func testUpdateMessagesCallsOnMessageChange() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        var callCount = 0
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { _ in callCount += 1 }
        )
        
        provider.updateMessages([.openai(.user(.init(content: "Test")))])
        
        #expect(callCount == 1)
    }
    
    @Test("appendMessage adds message to chat")
    func testAppendMessage() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)
        
        let newMessage = Message.openai(.user(.init(content: "Appended")))
        provider.appendMessage(newMessage)
        
        #expect(provider.messages.count == 1)
        #expect(provider.messages[0].id == newMessage.id)
    }
    
    @Test("appendMessage calls onMessage callback")
    func testAppendMessageCallsOnMessage() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        var receivedMessage: Message?
        let provider = ChatProvider()
        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessage: { msg in receivedMessage = msg }
        )
        
        let newMessage = Message.openai(.user(.init(content: "Test")))
        provider.appendMessage(newMessage)
        
        #expect(receivedMessage?.id == newMessage.id)
    }
    
    @Test("updateMessage by ID updates correct message")
    func testUpdateMessageById() {
        let originalMsg = Message.openai(.assistant(.init(content: "Original", toolCalls: nil, audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [originalMsg])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)
        
        let updatedMsg = Message.openai(.assistant(.init(id: originalMsg.id, content: "Updated", toolCalls: nil, audio: nil)))
        provider.updateMessage(id: originalMsg.id, with: updatedMsg)
        
        #expect(provider.messages.count == 1)
        if case .openai(let msg, _) = provider.messages[0], case .assistant(let assistant) = msg {
            #expect(assistant.content == "Updated")
        }
    }
    
    @Test("updateMessage with invalid ID does nothing")
    func testUpdateMessageInvalidId() {
        let originalMsg = Message.openai(.assistant(.init(content: "Original", toolCalls: nil, audio: nil)))
        let chat = Chat(id: UUID(), gameId: "test", messages: [originalMsg])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)
        
        let updatedMsg = Message.openai(.assistant(.init(content: "Updated", toolCalls: nil, audio: nil)))
        provider.updateMessage(id: "non-existent-id", with: updatedMsg)
        
        // Original message should be unchanged
        #expect(provider.messages.count == 1)
        if case .openai(let msg, _) = provider.messages[0], case .assistant(let assistant) = msg {
            #expect(assistant.content == "Original")
        }
    }
    
    @Test("setStatus updates chat status")
    func testSetStatus() {
        let chat = Chat(id: UUID(), gameId: "test", messages: [])
        let model = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Agent"))
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [model])
        
        let provider = ChatProvider()
        provider.setup(chat: chat, currentModel: model, currentSource: source)
        
        #expect(provider.status == .idle)
        
        provider.setStatus(.loading)
        #expect(provider.status == .loading)
        
        provider.setStatus(.idle)
        #expect(provider.status == .idle)
    }
}

// MARK: - Mock Tools for ChatProvider Tests

import JSONSchema

/// A simple mock tool for testing ChatProvider
struct MockTestTool: AgentToolProtocol {
    var toolType: AgentToolType { .regular }
    var name: String { "test_tool" }
    var description: String { "A test tool" }
    var inputType: any Decodable.Type { Args.self }
    var parameters: JSONSchema {
        // swiftlint:disable:next force_try
        try! JSONSchema(jsonString: """
            {"type": "object", "properties": {"input": {"type": "string"}}, "required": ["input"]}
            """)
    }

    struct Args: Decodable {
        let input: String
    }

    struct Output: Encodable {
        let result: String
    }

    func invoke(args: any Decodable, originalArgs: String) async throws -> any Encodable {
        return Output(result: "test result")
    }

    func invoke(argsData: Data, originalArgs: String) async throws -> any Encodable {
        return Output(result: "test result")
    }
}
