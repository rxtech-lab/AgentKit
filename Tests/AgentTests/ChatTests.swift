import Foundation
import Testing

@testable import Agent

@MainActor
struct ChatTests {

    // MARK: - Message Codable Tests

    @Test func testMessageOpenAIUserCodable() throws {
        let userMsg = OpenAIUserMessage(id: "user-1", content: "Hello")
        let message = Message.openai(.user(userMsg))

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        if case .openai(.user(let decodedUser), _) = decoded {
            #expect(decodedUser.content == "Hello")
            #expect(decodedUser.role == .user)
        } else {
            Issue.record("Expected openai user message")
        }
    }

    @Test func testMessageOpenAIAssistantCodable() throws {
        let assistantMsg = OpenAIAssistantMessage(
            id: "assistant-1", content: "Hi there", toolCalls: nil, audio: nil)
        let message = Message.openai(.assistant(assistantMsg))

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        if case .openai(.assistant(let decodedAssistant), _) = decoded {
            #expect(decodedAssistant.content == "Hi there")
            #expect(decodedAssistant.role == .assistant)
        } else {
            Issue.record("Expected openai assistant message")
        }
    }

    @Test func testMessageOpenAISystemCodable() throws {
        let systemMsg = OpenAISystemMessage(id: "system-1", content: "Be helpful")
        let message = Message.openai(.system(systemMsg))

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        if case .openai(.system(let decodedSystem), _) = decoded {
            #expect(decodedSystem.content == "Be helpful")
            #expect(decodedSystem.role == .system)
        } else {
            Issue.record("Expected openai system message")
        }
    }

    @Test func testMessageOpenAIToolCodable() throws {
        let toolMsg = OpenAIToolMessage(id: "tool-1", content: "Result", toolCallId: "call_123")
        let message = Message.openai(.tool(toolMsg))

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        if case .openai(.tool(let decodedTool), _) = decoded {
            #expect(decodedTool.content == "Result")
            #expect(decodedTool.toolCallId == "call_123")
            #expect(decodedTool.role == .tool)
        } else {
            Issue.record("Expected openai tool message")
        }
    }

    @Test func testMessageOpenAIAssistantWithToolCallsCodable() throws {
        let toolCalls = [
            OpenAIToolCall(
                id: "call_1",
                type: .function,
                function: .init(name: "get_weather", arguments: "{\"location\": \"NYC\"}")
            )
        ]
        let assistantMsg = OpenAIAssistantMessage(
            id: "assistant-2", content: nil, toolCalls: toolCalls, audio: nil)
        let message = Message.openai(.assistant(assistantMsg))

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)

        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        if case .openai(.assistant(let decodedAssistant), _) = decoded {
            #expect(decodedAssistant.content == nil)
            #expect(decodedAssistant.toolCalls?.count == 1)
            #expect(decodedAssistant.toolCalls?.first?.id == "call_1")
            #expect(decodedAssistant.toolCalls?.first?.function?.name == "get_weather")
        } else {
            Issue.record("Expected openai assistant message with tool calls")
        }
    }

    @Test func testMessageIdProperty() {
        let userMsg = OpenAIUserMessage(id: "test-id", content: "Test")
        let message = Message.openai(.user(userMsg))
        #expect(message.id == "test-id")
    }

    @Test func testMessageHashable() {
        let userMsg1 = OpenAIUserMessage(id: "id-1", content: "Hello")
        let userMsg2 = OpenAIUserMessage(id: "id-2", content: "World")
        let message1 = Message.openai(.user(userMsg1))
        let message2 = Message.openai(.user(userMsg2))
        let message1Duplicate = Message.openai(.user(userMsg1))

        var set: Set<Message> = []
        set.insert(message1)
        set.insert(message2)
        set.insert(message1Duplicate)

        #expect(set.count == 2)
    }

    // MARK: - Chat Tests

    @Test func testChatInit() {
        let id = UUID()
        let messages = [Message.openai(.user(OpenAIUserMessage(content: "Hello")))]
        let chat = Chat(id: id, gameId: "game-1", messages: messages)

        #expect(chat.id == id)
        #expect(chat.gameId == "game-1")
        #expect(chat.messages.count == 1)
    }

    @Test func testChatEquatable() {
        let id = UUID()
        let chat1 = Chat(id: id, gameId: "game-1", messages: [])
        let chat2 = Chat(id: id, gameId: "game-1", messages: [])
        let chat3 = Chat(id: UUID(), gameId: "game-2", messages: [])

        #expect(chat1 == chat2)
        #expect(chat1 != chat3)
    }

    @Test func testChatHashable() {
        let id1 = UUID()
        let id2 = UUID()
        let chat1 = Chat(id: id1, gameId: "game-1", messages: [])
        let chat2 = Chat(id: id2, gameId: "game-2", messages: [])

        var set: Set<Chat> = []
        set.insert(chat1)
        set.insert(chat2)

        #expect(set.count == 2)
    }

    // MARK: - ChatStatus Tests

    @Test func testChatStatusCases() {
        let idle = ChatStatus.idle
        let loading = ChatStatus.loading

        if case .idle = idle {
            // Success
        } else {
            Issue.record("Expected idle status")
        }

        if case .loading = loading {
            // Success
        } else {
            Issue.record("Expected loading status")
        }
    }
    
    // MARK: - Message isUpdating Tests
    
    @Test func testMessageIsUpdatingDefaultFalse() {
        let userMsg = OpenAIUserMessage(content: "Hello")
        let message = Message.openai(.user(userMsg))
        
        #expect(message.isUpdating == false)
    }
    
    @Test func testMessageIsUpdatingTrue() {
        let assistantMsg = OpenAIAssistantMessage(content: "Response", toolCalls: nil, audio: nil)
        let message = Message.openai(.assistant(assistantMsg), isUpdating: true)
        
        #expect(message.isUpdating == true)
    }
    
    @Test func testMessageWithUpdatingCreatesNewMessage() {
        let assistantMsg = OpenAIAssistantMessage(content: "Response", toolCalls: nil, audio: nil)
        let message = Message.openai(.assistant(assistantMsg), isUpdating: false)
        
        let updatingMessage = message.withUpdating(true)
        
        #expect(message.isUpdating == false)
        #expect(updatingMessage.isUpdating == true)
        #expect(message.id == updatingMessage.id)
    }
    
    @Test func testMessageIsUpdatingCodable() throws {
        let assistantMsg = OpenAIAssistantMessage(content: "Response", toolCalls: nil, audio: nil)
        let message = Message.openai(.assistant(assistantMsg), isUpdating: true)
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)
        
        #expect(decoded.isUpdating == true)
    }
    
    @Test func testMessageIsUpdatingFalseCodable() throws {
        let userMsg = OpenAIUserMessage(content: "Hello")
        let message = Message.openai(.user(userMsg), isUpdating: false)
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)
        
        // isUpdating defaults to false when not present in JSON
        #expect(decoded.isUpdating == false)
    }
    
    // MARK: - Generic Message Type Tests
    
    @Test func testUserMessageInit() {
        let msg = UserMessage(id: "user-1", content: "Hello world")
        
        #expect(msg.id == "user-1")
        #expect(msg.content == "Hello world")
    }
    
    @Test func testUserMessageDefaultId() {
        let msg = UserMessage(content: "Hello")
        
        #expect(!msg.id.isEmpty)
        #expect(msg.content == "Hello")
    }
    
    @Test func testAssistantMessageInit() {
        let toolCalls = [ToolCall(id: "tc-1", name: "get_weather", arguments: "{}")]
        let reasoning = ReasoningContent(text: "Thinking...", summary: "Summary")
        let msg = AssistantMessage(
            id: "asst-1",
            content: "Hello",
            toolCalls: toolCalls,
            reasoning: reasoning
        )
        
        #expect(msg.id == "asst-1")
        #expect(msg.content == "Hello")
        #expect(msg.toolCalls?.count == 1)
        #expect(msg.toolCalls?.first?.name == "get_weather")
        #expect(msg.reasoning?.text == "Thinking...")
        #expect(msg.reasoning?.summary == "Summary")
    }
    
    @Test func testAssistantMessageMinimal() {
        let msg = AssistantMessage(content: "Simple response")
        
        #expect(!msg.id.isEmpty)
        #expect(msg.content == "Simple response")
        #expect(msg.toolCalls == nil)
        #expect(msg.reasoning == nil)
    }
    
    @Test func testSystemMessageInit() {
        let msg = SystemMessage(id: "sys-1", content: "You are helpful")
        
        #expect(msg.id == "sys-1")
        #expect(msg.content == "You are helpful")
    }
    
    @Test func testToolMessageInit() {
        let msg = ToolMessage(
            id: "tool-1",
            toolCallId: "tc-1",
            name: "get_weather",
            content: "{\"temp\": 72}"
        )
        
        #expect(msg.id == "tool-1")
        #expect(msg.toolCallId == "tc-1")
        #expect(msg.name == "get_weather")
        #expect(msg.content == "{\"temp\": 72}")
    }
    
    @Test func testToolCallInit() {
        let tc = ToolCall(id: "tc-1", name: "search", arguments: "{\"query\": \"hello\"}")
        
        #expect(tc.id == "tc-1")
        #expect(tc.name == "search")
        #expect(tc.arguments == "{\"query\": \"hello\"}")
    }
    
    @Test func testReasoningContentInit() {
        let rc = ReasoningContent(text: "Thinking about this...", summary: "I thought")
        
        #expect(rc.text == "Thinking about this...")
        #expect(rc.summary == "I thought")
    }
    
    @Test func testReasoningContentPartial() {
        let textOnly = ReasoningContent(text: "Some reasoning")
        let summaryOnly = ReasoningContent(summary: "Just a summary")
        
        #expect(textOnly.text == "Some reasoning")
        #expect(textOnly.summary == nil)
        #expect(summaryOnly.text == nil)
        #expect(summaryOnly.summary == "Just a summary")
    }
    
    // MARK: - GenericMessage Tests
    
    @Test func testGenericMessageUserRole() {
        let genericMsg = GenericMessage.user(UserMessage(content: "Hello"))
        
        #expect(genericMsg.role == .user)
        #expect(genericMsg.content == "Hello")
    }
    
    @Test func testGenericMessageAssistantRole() {
        let genericMsg = GenericMessage.assistant(AssistantMessage(content: "Hi there"))
        
        #expect(genericMsg.role == .assistant)
        #expect(genericMsg.content == "Hi there")
    }
    
    @Test func testGenericMessageSystemRole() {
        let genericMsg = GenericMessage.system(SystemMessage(content: "Be helpful"))
        
        #expect(genericMsg.role == .system)
        #expect(genericMsg.content == "Be helpful")
    }
    
    @Test func testGenericMessageToolRole() {
        let genericMsg = GenericMessage.tool(ToolMessage(toolCallId: "tc-1", content: "Result"))
        
        #expect(genericMsg.role == .tool)
        #expect(genericMsg.content == "Result")
    }
    
    @Test func testGenericMessageId() {
        let userMsg = UserMessage(id: "test-id", content: "Hello")
        let genericMsg = GenericMessage.user(userMsg)
        
        #expect(genericMsg.id == "test-id")
    }
    
    @Test func testGenericMessageCodable() throws {
        let genericMsg = GenericMessage.user(UserMessage(id: "user-1", content: "Hello"))
        
        let encoded = try JSONEncoder().encode(genericMsg)
        let decoded = try JSONDecoder().decode(GenericMessage.self, from: encoded)
        
        #expect(decoded.id == "user-1")
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello")
    }
    
    @Test func testGenericMessageAssistantCodable() throws {
        let toolCalls = [ToolCall(id: "tc-1", name: "test", arguments: "{}")]
        let reasoning = ReasoningContent(text: "thinking", summary: "thought")
        let assistantMsg = AssistantMessage(
            id: "asst-1",
            content: "Response",
            toolCalls: toolCalls,
            reasoning: reasoning
        )
        let genericMsg = GenericMessage.assistant(assistantMsg)
        
        let encoded = try JSONEncoder().encode(genericMsg)
        let decoded = try JSONDecoder().decode(GenericMessage.self, from: encoded)
        
        #expect(decoded.id == "asst-1")
        #expect(decoded.role == .assistant)
        if case .assistant(let decodedAssistant) = decoded {
            #expect(decodedAssistant.content == "Response")
            #expect(decodedAssistant.toolCalls?.count == 1)
            #expect(decodedAssistant.reasoning?.text == "thinking")
        } else {
            Issue.record("Expected assistant message")
        }
    }
    
    // MARK: - GenericMessage OpenAI Conversion Tests
    
    @Test func testGenericMessageFromOpenAIUser() {
        let openAIUser = OpenAIUserMessage(id: "user-1", content: "Hello")
        let generic = GenericMessage.from(openAI: .user(openAIUser))
        
        #expect(generic.id == "user-1")
        #expect(generic.role == .user)
        #expect(generic.content == "Hello")
    }
    
    @Test func testGenericMessageFromOpenAIAssistant() {
        let toolCalls = [
            OpenAIToolCall(
                id: "tc-1",
                type: .function,
                function: .init(name: "test", arguments: "{}")
            )
        ]
        let openAIAssistant = OpenAIAssistantMessage(
            id: "asst-1",
            content: "Response",
            toolCalls: toolCalls,
            audio: nil
        )
        let generic = GenericMessage.from(openAI: .assistant(openAIAssistant))
        
        #expect(generic.id == "asst-1")
        #expect(generic.role == .assistant)
        #expect(generic.content == "Response")
        if case .assistant(let assistantMsg) = generic {
            #expect(assistantMsg.toolCalls?.count == 1)
            #expect(assistantMsg.toolCalls?.first?.id == "tc-1")
            #expect(assistantMsg.toolCalls?.first?.name == "test")
        }
    }
    
    @Test func testGenericMessageFromOpenAISystem() {
        let openAISystem = OpenAISystemMessage(id: "sys-1", content: "Be helpful")
        let generic = GenericMessage.from(openAI: .system(openAISystem))
        
        #expect(generic.id == "sys-1")
        #expect(generic.role == .system)
        #expect(generic.content == "Be helpful")
    }
    
    @Test func testGenericMessageFromOpenAITool() {
        let openAITool = OpenAIToolMessage(id: "tool-1", content: "Result", toolCallId: "tc-1", name: "test")
        let generic = GenericMessage.from(openAI: .tool(openAITool))
        
        #expect(generic.id == "tool-1")
        #expect(generic.role == .tool)
        #expect(generic.content == "Result")
        if case .tool(let toolMsg) = generic {
            #expect(toolMsg.toolCallId == "tc-1")
            #expect(toolMsg.name == "test")
        }
    }
    
    @Test func testGenericMessageToOpenAIUser() {
        let userMsg = UserMessage(id: "user-1", content: "Hello")
        let generic = GenericMessage.user(userMsg)
        let openAI = generic.toOpenAI()
        
        if case .user(let openAIUser) = openAI {
            #expect(openAIUser.id == "user-1")
            #expect(openAIUser.content == "Hello")
        } else {
            Issue.record("Expected OpenAI user message")
        }
    }
    
    @Test func testGenericMessageToOpenAIAssistant() {
        let toolCalls = [ToolCall(id: "tc-1", name: "test", arguments: "{}")]
        let assistantMsg = AssistantMessage(
            id: "asst-1",
            content: "Response",
            toolCalls: toolCalls,
            reasoning: ReasoningContent(text: "thinking")
        )
        let generic = GenericMessage.assistant(assistantMsg)
        let openAI = generic.toOpenAI()
        
        if case .assistant(let openAIAssistant) = openAI {
            #expect(openAIAssistant.id == "asst-1")
            #expect(openAIAssistant.content == "Response")
            #expect(openAIAssistant.toolCalls?.count == 1)
            #expect(openAIAssistant.reasoning == "thinking")
        } else {
            Issue.record("Expected OpenAI assistant message")
        }
    }
    
    // MARK: - Message Convenience Initializer Tests
    
    @Test func testMessageUserConvenience() {
        let message = Message.user("Hello world", id: "user-1")
        
        #expect(message.id == "user-1")
        #expect(message.role == .user)
        #expect(message.content == "Hello world")
        #expect(message.isUpdating == false)
    }
    
    @Test func testMessageUserConvenienceWithUpdating() {
        let message = Message.user("Hello", isUpdating: true)
        
        #expect(message.role == .user)
        #expect(message.content == "Hello")
        #expect(message.isUpdating == true)
    }
    
    @Test func testMessageAssistantConvenience() {
        let toolCalls = [ToolCall(id: "tc-1", name: "test", arguments: "{}")]
        let reasoning = ReasoningContent(text: "thinking")
        let message = Message.assistant(
            "Response",
            id: "asst-1",
            toolCalls: toolCalls,
            reasoning: reasoning,
            isUpdating: true
        )
        
        #expect(message.id == "asst-1")
        #expect(message.role == .assistant)
        #expect(message.content == "Response")
        #expect(message.isUpdating == true)
    }
    
    @Test func testMessageSystemConvenience() {
        let message = Message.system("Be helpful", id: "sys-1")
        
        #expect(message.id == "sys-1")
        #expect(message.role == .system)
        #expect(message.content == "Be helpful")
        #expect(message.isUpdating == false)
    }
    
    @Test func testMessageToolConvenience() {
        let message = Message.tool(
            toolCallId: "tc-1",
            content: "Result",
            name: "test",
            id: "tool-1"
        )
        
        #expect(message.id == "tool-1")
        #expect(message.role == .tool)
        #expect(message.content == "Result")
    }
    
    @Test func testMessageAsGenericProperty() {
        let openAIMsg = Message.openai(.user(OpenAIUserMessage(id: "user-1", content: "Hello")))
        let generic = openAIMsg.asGeneric
        
        #expect(generic.id == "user-1")
        #expect(generic.role == .user)
        #expect(generic.content == "Hello")
    }
    
    @Test func testMessageRoleProperty() {
        let userMsg = Message.user("Hello")
        let assistantMsg = Message.assistant("Hi")
        let systemMsg = Message.system("Be helpful")
        let toolMsg = Message.tool(toolCallId: "tc-1", content: "Result")
        
        #expect(userMsg.role == .user)
        #expect(assistantMsg.role == .assistant)
        #expect(systemMsg.role == .system)
        #expect(toolMsg.role == .tool)
    }
    
    @Test func testMessageContentProperty() {
        let userMsg = Message.user("Hello world")
        let assistantMsg = Message.assistant(nil)
        
        #expect(userMsg.content == "Hello world")
        #expect(assistantMsg.content == nil)
    }
    
    @Test func testMessageGenericCodable() throws {
        let message = Message.user("Hello", id: "user-1")
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)
        
        #expect(decoded.id == "user-1")
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello")
    }
    
    @Test func testMessageGenericWithUpdatingCodable() throws {
        let message = Message.assistant("Response", id: "asst-1", isUpdating: true)
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)
        
        #expect(decoded.id == "asst-1")
        #expect(decoded.isUpdating == true)
    }
}
