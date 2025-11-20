//
//  GeminiClientTests.swift
//  AgentKit
//
//  Created by Copilot
//

import Foundation
import Vapor
import XCTest

@testable import Agent

final class GeminiClientTests: XCTestCase {
    var app: Application!
    var controller: GeminiChatController!
    var client: GeminiClient!

    override func setUp() async throws {
        // Set up Vapor application for testing
        app = try await Application.make(.testing)

        // Configure the mock server
        controller = await GeminiChatController()
        await controller.registerRoutes(on: app)

        // Find a free port for testing
        let port = 8124  // Different port from OpenAI tests
        app.http.server.configuration.port = port

        // Start the server
        try await app.startup()

        // Initialize the client with the testing server URL
        let baseURL = URL(string: "http://localhost:\(port)")!
        client = GeminiClient(baseURL: baseURL, apiKey: "test-api-key")
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
        let mockResponse = GeminiModelMessage(
            parts: [
                .text(GeminiTextPart(text: "This is a test response from the mock Gemini server."))
            ]
        )
        controller.mockChatResponse([mockResponse])

        // Create a user message for testing
        let userMessage = GeminiUserMessage(text: "Hello")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "gemini-pro")

        // Collect all responses
        var receivedText = ""
        var responseCount = 0

        // Call the client with streaming response
        let stream = await client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel,
            tools: [
                GeminiTool(functionDeclarations: [
                    GeminiTool.FunctionDeclaration(
                        name: "getWeather",
                        description: "Get weather by city",
                        parameters: .object(
                            title: "weather",
                            properties: [
                                "city": .string(description: "name of the city")
                            ],
                            required: ["city"]
                        )
                    )
                ])
            ]
        )

        // Process the stream
        for try await message in stream.stream {
            if case .model(let modelMessage) = message {
                responseCount += 1

                for part in modelMessage.parts {
                    if case .text(let textPart) = part {
                        receivedText = textPart.text
                    }
                }
            }
        }

        // Assert the expected results
        XCTAssertGreaterThan(responseCount, 0, "Should receive at least one streaming response")
        XCTAssertEqual(receivedText, "This is a test response from the mock Gemini server.")
    }

    @MainActor
    func testStreamingResponseCancellation() async throws {
        // Set up the mock response with multiple chunks
        let mockResponses = [
            GeminiModelMessage(parts: [.text(GeminiTextPart(text: "This "))]),
            GeminiModelMessage(parts: [.text(GeminiTextPart(text: "is "))]),
            GeminiModelMessage(parts: [.text(GeminiTextPart(text: "a "))]),
            GeminiModelMessage(parts: [.text(GeminiTextPart(text: "test."))]),
        ]
        controller.mockChatResponse(mockResponses)

        // Create a user message for testing
        let userMessage = GeminiUserMessage(text: "Hello")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "gemini-pro")

        // Call the client with streaming response
        let (stream, cancellable) = await client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel
        )

        // Cancel immediately
        await cancellable.cancel()
        
        // Capture received messages
        var receivedMessages = 0

        do {
            for try await _ in stream {
                receivedMessages += 1
            }
        } catch {
            XCTFail("Stream should not throw an error when cancelled: \(error)")
        }

        // Assert that we received no messages or very few after cancellation
        XCTAssertLessThanOrEqual(receivedMessages, 1, "Should receive very few or no messages after cancellation")
    }

    @MainActor
    func testStreamingResponseWithFunctionCall() async throws {
        // Set up the mock response with a function call
        let mockResponse = GeminiModelMessage(
            parts: [
                .functionCall(GeminiFunctionCall(
                    name: "getWeather",
                    args: ["city": "San Francisco"]
                ))
            ]
        )
        controller.mockChatResponse([mockResponse])

        // Create a user message for testing
        let userMessage = GeminiUserMessage(text: "What's the weather in San Francisco?")

        // Use a test model
        let testModel = OpenAICompatibleModel(id: "gemini-pro")

        // Collect all responses
        var receivedFunctionCalls: [GeminiFunctionCall] = []
        var responseCount = 0

        // Call the client with streaming response
        let stream = await client.generateStreamResponse(
            systemText: "You are a helpful assistant.",
            message: userMessage,
            model: testModel,
            tools: [
                GeminiTool(functionDeclarations: [
                    GeminiTool.FunctionDeclaration(
                        name: "getWeather",
                        description: "Get weather by city",
                        parameters: .object(
                            title: "weather",
                            properties: [
                                "city": .string(description: "name of the city")
                            ],
                            required: ["city"]
                        )
                    )
                ])
            ]
        )

        // Process the stream
        for try await message in stream.stream {
            if case .model(let modelMessage) = message {
                responseCount += 1

                for part in modelMessage.parts {
                    if case .functionCall(let functionCall) = part {
                        receivedFunctionCalls.append(functionCall)
                    }
                }
            }
        }

        // Assert the expected results
        XCTAssertGreaterThan(responseCount, 0, "Should receive at least one streaming response")
        XCTAssertEqual(receivedFunctionCalls.count, 1, "Should receive one function call")
        XCTAssertEqual(receivedFunctionCalls.first?.name, "getWeather")
        XCTAssertEqual(receivedFunctionCalls.first?.args["city"], "San Francisco")
    }
}
