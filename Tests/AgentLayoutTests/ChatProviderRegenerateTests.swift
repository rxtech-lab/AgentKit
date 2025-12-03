//
//  ChatProviderRegenerateTests.swift
//  AgentLayoutTests
//
//  Tests for ChatProvider.regenerate function
//

import Foundation
import SwiftUI
import Testing
import Vapor
import XCTest

@testable import Agent
@testable import AgentLayout

// MARK: - Shared Mock Server for Regenerate Tests

@MainActor
final class RegenerateSharedMockServer {
    static let shared = RegenerateSharedMockServer()

    private var app: Application?
    private var isRunning = false
    let controller = RegenerateMockOpenAIChatController()
    private(set) var port: Int = 0

    private init() {}

    func ensureRunning() async throws {
        guard !isRunning else { return }

        // Try random ports with retry, creating fresh app each time
        var lastError: Error?
        for _ in 0..<10 {
            // Use custom environment to avoid parsing command-line args from Swift Testing
            let application = try await Application.make(.custom(name: "testing"))
            let randomPort = Int.random(in: 10000...60000)

            controller.registerRoutes(on: application)

            do {
                // Use server.start instead of startup to avoid command parsing
                try await application.server.start(address: .hostname("localhost", port: randomPort))
                self.port = randomPort
                self.app = application
                self.isRunning = true
                return
            } catch {
                lastError = error
                // Shutdown the failed application before trying again
                try? await application.asyncShutdown()
                continue
            }
        }

        throw lastError ?? NSError(
            domain: "TestError", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to find available port"])
    }

    func shutdown() async throws {
        if let app = app {
            await app.server.shutdown()
            try await app.asyncShutdown()
        }
        app = nil
        isRunning = false
    }
}

// MARK: - Helper Functions

@MainActor
private func createUserMessage(_ content: String, id: String? = nil) -> Message {
    Message.openai(.user(.init(id: id ?? UUID().uuidString, content: content)))
}

@MainActor
private func createAssistantMessage(_ content: String, id: String? = nil) -> Message {
    Message.openai(
        .assistant(
            .init(
                id: id ?? UUID().uuidString,
                content: content,
                toolCalls: nil,
                audio: nil
            )))
}

@MainActor
private func createChat(messages: [Message]) -> Chat {
    Chat(id: UUID(), gameId: "test", messages: messages)
}

@MainActor
private func waitForGenerationComplete(
    provider: ChatProvider,
    timeout: TimeInterval = 5.0
) async throws {
    let start = Date()

    // Wait a bit for the status to transition to loading
    try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

    // Then wait for it to become idle again
    while provider.status == .loading {
        if Date().timeIntervalSince(start) > timeout {
            throw NSError(
                domain: "TestError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for generation"])
        }
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    }
}

// MARK: - Swift Testing Suite for Regenerate Tests

@MainActor
@Suite("ChatProvider Regenerate Tests", .serialized)
struct ChatProviderRegenerateTests {

    init() async throws {
        try await RegenerateSharedMockServer.shared.ensureRunning()
    }

    private func createSource() -> Source {
        let port = RegenerateSharedMockServer.shared.port
        return Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:\(port)")!),
            models: []
        )
    }

    private func createModel() -> Model {
        Model.custom(CustomModel(id: "gpt-4"))
    }

    private var controller: RegenerateMockOpenAIChatController {
        RegenerateSharedMockServer.shared.controller
    }

    // MARK: - Test: Regenerate User Message

    @Test("Regenerating user message keeps it and replaces subsequent messages")
    func testRegenerateUserMessage() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let userMsgId = UUID().uuidString
        let userMsg = createUserMessage("Hello", id: userMsgId)
        let assistantMsg = createAssistantMessage("Hi there!")
        let chat = createChat(messages: [userMsg, assistantMsg])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 2)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "Hello! How can I help?", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: userMsgId)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 2 messages: original user + new assistant
        #expect(provider.messages.count == 2)

        // User message should be preserved with same ID
        #expect(provider.messages[0].id == userMsgId)

        // New assistant message should have new content
        if case .openai(let openAIMsg) = provider.messages[1],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "Hello! How can I help?")
        } else {
            Issue.record("Expected assistant message at index 1")
        }
    }

    @Test("Regenerating user message in middle of conversation keeps prior messages")
    func testRegenerateUserMessageInMiddle() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let user1 = createUserMessage("Hello")
        let assistant1 = createAssistantMessage("Hi there!")
        let user2Id = UUID().uuidString
        let user2 = createUserMessage("How are you?", id: user2Id)
        let assistant2 = createAssistantMessage("I'm doing great!")

        let chat = createChat(messages: [user1, assistant1, user2, assistant2])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 4)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "I'm doing fantastic!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: user2Id)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 4 messages: user1, assistant1, user2 (preserved), new assistant
        #expect(provider.messages.count == 4)

        // First 3 messages should be preserved
        #expect(provider.messages[0].id == user1.id)
        #expect(provider.messages[1].id == assistant1.id)
        #expect(provider.messages[2].id == user2Id)

        // Last message should be new assistant with new content
        if case .openai(let openAIMsg) = provider.messages[3],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "I'm doing fantastic!")
        } else {
            Issue.record("Expected assistant message at index 3")
        }
    }

    @Test("Regenerating first user message removes all subsequent messages")
    func testRegenerateFirstUserMessage() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let user1Id = UUID().uuidString
        let user1 = createUserMessage("Hello", id: user1Id)
        let assistant1 = createAssistantMessage("Hi there!")
        let user2 = createUserMessage("How are you?")
        let assistant2 = createAssistantMessage("I'm doing great!")

        let chat = createChat(messages: [user1, assistant1, user2, assistant2])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 4)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "New response!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: user1Id)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 2 messages: user1 (preserved) + new assistant
        #expect(provider.messages.count == 2)

        // User1 should be preserved
        #expect(provider.messages[0].id == user1Id)

        // assistant1, user2, assistant2 should be deleted
        let messageIds = provider.messages.map { $0.id }
        #expect(!messageIds.contains(assistant1.id))
        #expect(!messageIds.contains(user2.id))
        #expect(!messageIds.contains(assistant2.id))

        // New assistant message should have new content
        if case .openai(let openAIMsg) = provider.messages[1],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "New response!")
        } else {
            Issue.record("Expected assistant message at index 1")
        }
    }

    // MARK: - Test: Regenerate First Assistant Message

    @Test("Regenerating first assistant message replaces it with new response")
    func testRegenerateFirstAssistantMessage() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let userMsg = createUserMessage("Hello")
        let assistantMsgId = UUID().uuidString
        let assistantMsg = createAssistantMessage("Hi there!", id: assistantMsgId)
        let chat = createChat(messages: [userMsg, assistantMsg])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 2)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "Hello! How can I help?", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: assistantMsgId)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 2 messages: original user + new assistant
        #expect(provider.messages.count == 2)

        // User message should be preserved
        #expect(provider.messages[0].id == userMsg.id)

        // New assistant message should have new content and different ID
        if case .openai(let openAIMsg) = provider.messages[1],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "Hello! How can I help?")
            #expect(newAssistant.id != assistantMsgId)
        } else {
            Issue.record("Expected assistant message at index 1")
        }
    }

    // MARK: - Test: Regenerate Last Message

    @Test("Regenerating last message in multi-turn conversation")
    func testRegenerateLastMessage() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let user1 = createUserMessage("Hello")
        let assistant1 = createAssistantMessage("Hi there!")
        let user2 = createUserMessage("How are you?")
        let assistant2Id = UUID().uuidString
        let assistant2 = createAssistantMessage("I'm doing great!", id: assistant2Id)

        let chat = createChat(messages: [user1, assistant1, user2, assistant2])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 4)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "I'm doing fantastic!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: assistant2Id)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 4 messages
        #expect(provider.messages.count == 4)

        // First 3 messages should be preserved
        #expect(provider.messages[0].id == user1.id)
        #expect(provider.messages[1].id == assistant1.id)
        #expect(provider.messages[2].id == user2.id)

        // Last message should have new content
        if case .openai(let openAIMsg) = provider.messages[3],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "I'm doing fantastic!")
        } else {
            Issue.record("Expected assistant message at index 3")
        }
    }

    // MARK: - Test: Regenerate Middle Message Deletes Subsequent

    @Test("Regenerating middle message deletes all subsequent messages")
    func testRegenerateMiddleMessageDeletesSubsequent() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let user1 = createUserMessage("Hello")
        let assistant1Id = UUID().uuidString
        let assistant1 = createAssistantMessage("Hi there!", id: assistant1Id)
        let user2 = createUserMessage("How are you?")
        let assistant2 = createAssistantMessage("I'm doing great!")

        let chat = createChat(messages: [user1, assistant1, user2, assistant2])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        #expect(provider.messages.count == 4)

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "New response!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: assistant1Id)
        try await waitForGenerationComplete(provider: provider)

        // Should have exactly 2 messages: user1 + new assistant
        #expect(provider.messages.count == 2)

        // User1 should be preserved
        #expect(provider.messages[0].id == user1.id)

        // user2 and assistant2 should be deleted
        let messageIds = provider.messages.map { $0.id }
        #expect(!messageIds.contains(user2.id))
        #expect(!messageIds.contains(assistant2.id))

        // New assistant message should have new content
        if case .openai(let openAIMsg) = provider.messages[1],
            case .assistant(let newAssistant) = openAIMsg
        {
            #expect(newAssistant.content == "New response!")
        } else {
            Issue.record("Expected assistant message at index 1")
        }
    }

    // MARK: - Test: No Duplicate Messages

    @Test("Regeneration produces exactly one message, no duplicates")
    func testRegenerateNoDuplicates() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let userMsg = createUserMessage("Hello")
        let assistantMsgId = UUID().uuidString
        let assistantMsg = createAssistantMessage("Hi there!", id: assistantMsgId)
        let chat = createChat(messages: [userMsg, assistantMsg])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "New response!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: assistantMsgId)
        try await waitForGenerationComplete(provider: provider)

        // Count assistant messages
        let assistantMessages = provider.messages.filter { msg in
            if case .openai(let openAIMsg) = msg,
                case .assistant = openAIMsg
            {
                return true
            }
            return false
        }

        #expect(assistantMessages.count == 1, "Should have exactly one assistant message")
        #expect(provider.messages.count == 2, "Should have exactly 2 messages total")

        // Verify no duplicate IDs
        let allIds = provider.messages.map { $0.id }
        let uniqueIds = Set(allIds)
        #expect(allIds.count == uniqueIds.count, "Should have no duplicate message IDs")
    }

    // MARK: - Test: onMessageChange Callback

    @Test("Regenerate calls onMessageChange callback")
    func testRegenerateCallsOnMessageChange() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        var messageChangeCallCount = 0

        let userMsg = createUserMessage("Hello")
        let assistantMsgId = UUID().uuidString
        let assistantMsg = createAssistantMessage("Hi there!", id: assistantMsgId)
        let chat = createChat(messages: [userMsg, assistantMsg])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source,
            onMessageChange: { _ in messageChangeCallCount += 1 }
        )

        controller.mockChatResponse([
            OpenAIAssistantMessage(content: "New!", toolCalls: nil, audio: nil)
        ])

        provider.regenerate(messageId: assistantMsgId)
        try await waitForGenerationComplete(provider: provider)

        #expect(messageChangeCallCount >= 1, "onMessageChange should be called at least once")
    }

    // MARK: - Guard Tests

    @Test("Regenerate does nothing when chat is nil")
    func testRegenerateNoChat() async throws {
        let provider = ChatProvider()
        // Don't call setup - chat will be nil

        provider.regenerate(messageId: "some-id")

        #expect(provider.messages.isEmpty)
        #expect(provider.status == .idle)
    }

    @Test("Regenerate does nothing with invalid message ID")
    func testRegenerateInvalidMessageId() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        let userMsg = createUserMessage("Hello")
        let assistantMsg = createAssistantMessage("Hi there!")
        let chat = createChat(messages: [userMsg, assistantMsg])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        let originalMessageCount = provider.messages.count
        let originalUserMsgId = provider.messages[0].id
        let originalAssistantMsgId = provider.messages[1].id

        provider.regenerate(messageId: "non-existent-id")

        // Messages should be unchanged
        #expect(provider.messages.count == originalMessageCount)
        #expect(provider.messages[0].id == originalUserMsgId)
        #expect(provider.messages[1].id == originalAssistantMsgId)
        #expect(provider.status == .idle)
    }

    @Test("Regenerate does nothing when no user message found before target")
    func testRegenerateNoPriorUserMessage() async throws {
        let provider = ChatProvider()
        let source = createSource()
        let model = createModel()

        // Edge case: only assistant messages (unusual but possible)
        let assistant1 = createAssistantMessage("Message 1")
        let assistant2Id = UUID().uuidString
        let assistant2 = createAssistantMessage("Message 2", id: assistant2Id)
        let chat = createChat(messages: [assistant1, assistant2])

        provider.setup(
            chat: chat,
            currentModel: model,
            currentSource: source
        )

        let originalCount = provider.messages.count

        provider.regenerate(messageId: assistant2Id)

        // Messages should be unchanged since no user message was found
        #expect(provider.messages.count == originalCount)
        #expect(provider.status == .idle)
    }
}
