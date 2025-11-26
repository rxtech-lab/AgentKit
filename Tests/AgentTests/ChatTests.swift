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
        if case .openai(.user(let decodedUser)) = decoded {
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
        if case .openai(.assistant(let decodedAssistant)) = decoded {
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
        if case .openai(.system(let decodedSystem)) = decoded {
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
        if case .openai(.tool(let decodedTool)) = decoded {
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
        if case .openai(.assistant(let decodedAssistant)) = decoded {
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
}
