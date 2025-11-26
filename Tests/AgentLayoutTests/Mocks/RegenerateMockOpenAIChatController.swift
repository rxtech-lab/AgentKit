//
//  RegenerateMockOpenAIChatController.swift
//  AgentLayoutTests
//
//  Created for testing ChatProvider.regenerate
//

import Foundation
import Vapor

@testable import Agent

/// A controller that mocks OpenAI chat completion API responses for regenerate tests
@MainActor
class RegenerateMockOpenAIChatController {
    private var mockResponseQueue: [[OpenAIAssistantMessage]]

    init() {
        self.mockResponseQueue = []
    }

    /// Add a set of mock responses to be returned for a single request
    /// - Parameter responses: List of assistant messages to be returned as chunks for one request
    func mockChatResponse(_ responses: [OpenAIAssistantMessage]) {
        mockResponseQueue.append(responses)
    }

    /// Register routes for this controller on a Vapor router
    /// - Parameter routes: The router to register routes on
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
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
        return response
    }
}
