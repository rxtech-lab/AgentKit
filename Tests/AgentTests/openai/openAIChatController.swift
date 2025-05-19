//
//  openAIChatController.swift
//  AgentKit
//
//  Created by Qiwei Li on 5/19/25.
//

import Foundation
import Vapor

@testable import Agent

/// A controller that mocks OpenAI chat completion API responses
@MainActor
class OpenAIChatController {
    private var mockResponses: [OpenAIAssistantMessage]

    init() {
        self.mockResponses = []
    }

    /// Set mock responses to be returned in the streaming API
    /// - Parameter responses: List of assistant messages to be returned as chunks
    func mockChatResponse(_ responses: [OpenAIAssistantMessage]) {
        mockResponses = responses
    }

    /// Register routes for this controller on a Vapor router
    /// - Parameter routes: The router to register routes on
    func registerRoutes(on routes: RoutesBuilder) {
        // Register the endpoint that matches OpenAI's API
        let chatRoutes = routes.grouped("chat")
        chatRoutes.post("completions", use: handleChatCompletion)
    }

    private func handleChatCompletion(request: Request) async throws -> Response {
        let body = Response.Body(stream: { writer in
            Task {
                let mockResponses = await self.mockResponses
                let id = UUID().uuidString
                let created = Date().timeIntervalSince1970
                let model = "gpt-3.5-turbo"
                for response in mockResponses {
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
                    let jsonData = try JSONEncoder().encode(chunk)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                    _ = writer.write(.buffer(ByteBuffer(string: "data: \(jsonString)")))
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
