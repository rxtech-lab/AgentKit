//
//  OpenAIClientTests.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Foundation
import XCTest

@testable import Agent

final class OpenAIClientTests: XCTestCase {
    var client: OpenAIClient!

    override func setUp() async throws {
        // Initialize the client with the testing server URL
        let baseURL = URL(string: "http://localhost:1234")!
        client = OpenAIClient(baseURL: baseURL, apiKey: "test-api-key")
    }

    @MainActor
    func testStreamingResponseWithTextContent() async throws {
        // Create a user message for testing
        let userMessage = OpenAIUserMessage(content: "Hello")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "test-model")

        // Collect all responses
        var receivedContent = ""
        var receivedToolCalls: [OpenAIToolCall] = []
        var responseCount = 0

        // Call the client with streaming response
        let stream = await client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel,
            tools: [
                .init(
                    name: "getWeather", description: "Get weather by city",
                    parameters: .object(
                        title: "weather",
                        properties: [
                            "city": .string(description: "name of the city")
                        ], required: ["city"]), strict: true)
            ]
        )

        // Process the stream
        for try await message in stream {
            if case .assistant(let assistantMessage) = message {
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
}
