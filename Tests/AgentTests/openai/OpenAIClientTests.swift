//
//  OpenAIClientTests.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Vapor
import XCTVapor
import XCTest

@testable import Agent

final class OpenAIClientTests: XCTestCase {
    var app: Application!
    var controller: OpenAIChatController!
    var client: OpenAIClient!

    override func setUp() async throws {
        // Set up Vapor application for testing
        app = try await Application.make(.testing)

        // Configure the mock server
        controller = await OpenAIChatController()
        await controller.registerRoutes(on: app)

        // Find a free port for testing
        let port = 8123  // This could be dynamic in a real implementation
        app.http.server.configuration.port = port

        // Start the server
        try await app.startup()

        // Initialize the client with the testing server URL
        let baseURL = URL(string: "http://localhost:\(port)")!
        client = OpenAIClient(baseURL: baseURL, apiKey: "test-api-key")
    }

    override func tearDown() async throws {
        // Shut down the server
        try await app.asyncShutdown()
        app = nil
        controller = nil
        client = nil
    }

    @MainActor
    func testStreamingResponseWithTextContent() async throws {
        // Set up the mock response
        let mockResponse = OpenAIAssistantMessage(
            id: "mock-id",
            content: "This is a test response from the mock server.",
            toolCalls: nil,
            audio: nil
        )
        controller.mockChatResponse([mockResponse])

        // Create a user message for testing
        let userMessage = OpenAIUserMessage(content: "Hello")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "test-model")

        // Collect all responses
        var receivedContent = ""
        var receivedToolCalls: [OpenAIToolCall] = []
        var responseCount = 0

        // Call the client with streaming response
        let stream = client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel
        )

        // Process the stream
        for try await message in stream {
            if case .openai(.assistant(let assistantMessage)) = message {
                responseCount += 1

                if let content = assistantMessage.content {
                    receivedContent += content
                }

                if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                    receivedToolCalls.append(contentsOf: toolCalls)
                }
            }
        }

        // Assert the expected results
        XCTAssertGreaterThan(responseCount, 1, "Should receive multiple streaming responses")
        XCTAssertEqual(receivedContent, "This is a test response from the mock server.")
        XCTAssertTrue(receivedToolCalls.isEmpty, "Should not receive any tool calls")
    }

    @MainActor
    func testStreamingResponseWithToolCalls() async throws {
        // Create a tool call for testing
        let toolCall = OpenAIToolCall(
            id: "tool-call-id",
            type: .function,
            function: .init(
                name: "get_weather",
                arguments: "{\"location\":\"San Francisco\"}"
            )
        )

        // Set up the mock response with tool calls
        let mockResponse = OpenAIAssistantMessage(
            id: "mock-id",
            content: "Let me check the weather for you.",
            toolCalls: [toolCall],
            audio: nil
        )
        controller.mockChatResponse([mockResponse])

        // Create a user message for testing
        let userMessage = OpenAIUserMessage(content: "What's the weather in San Francisco?")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "test-model")

        // Collect all responses
        var receivedContent = ""
        var receivedToolCalls: [OpenAIToolCall] = []

        // Call the client with streaming response
        let stream = client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel
        )

        // Process the stream
        for try await message in stream {
            if case .openai(.assistant(let assistantMessage)) = message {
                if let content = assistantMessage.content {
                    receivedContent += content
                }

                if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                    receivedToolCalls.append(contentsOf: toolCalls)
                }
            }
        }

        // Assert the expected results
        XCTAssertEqual(receivedContent, "Let me check the weather for you.")
        XCTAssertEqual(receivedToolCalls.count, 1)
        XCTAssertEqual(receivedToolCalls[0].id, "tool-call-id")
        XCTAssertEqual(receivedToolCalls[0].type, .function)
        XCTAssertEqual(receivedToolCalls[0].function.name, "get_weather")
        XCTAssertEqual(receivedToolCalls[0].function.arguments, "{\"location\":\"San Francisco\"}")
    }

    @MainActor
    func testMultipleChunkedResponses() async throws {
        // Set up multiple mock responses to simulate a more complex conversation
        let firstResponse = OpenAIAssistantMessage(
            id: "chunk-1",
            content: "This is the first chunk of the response. ",
            toolCalls: nil,
            audio: nil
        )

        let secondResponse = OpenAIAssistantMessage(
            id: "chunk-2",
            content: "This is the second chunk of the response.",
            toolCalls: nil,
            audio: nil
        )

        controller.mockChatResponse([firstResponse, secondResponse])

        // Create a user message for testing
        let userMessage = OpenAIUserMessage(content: "Give me a complex response")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "test-model")

        // Collect all responses
        var receivedResponses: [String] = []

        // Call the client with streaming response
        let stream = client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel
        )

        // Process the stream
        for try await message in stream {
            if case .openai(.assistant(let assistantMessage)) = message {
                if let content = assistantMessage.content {
                    receivedResponses.append(content)
                }
            }
        }

        // Combine all responses to check the full content
        let fullResponse = receivedResponses.joined()

        // Assert the expected results
        XCTAssertGreaterThan(
            receivedResponses.count, 2, "Should receive multiple streaming response chunks")

        // The full response should contain both chunks (may be split differently due to the chunking logic)
        XCTAssertTrue(fullResponse.contains("This is the first chunk of the response"))
        XCTAssertTrue(fullResponse.contains("This is the second chunk of the response"))
    }
}
