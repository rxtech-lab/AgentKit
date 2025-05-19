//
//  OpenAIClientTests.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Foundation
import Vapor
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
        let port = 8123 // This could be dynamic in a real implementation
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
            toolCalls: [
                .init(id: "tool1", type: .function, function: .init(name: "getWeather", arguments: ""))
            ],
            audio: nil)
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
            ])

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
        XCTAssertEqual(receivedToolCalls.count, 1, "Should receive one tool call")
    }
}
