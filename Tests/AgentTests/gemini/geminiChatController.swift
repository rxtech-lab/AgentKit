//
//  geminiChatController.swift
//  AgentKit
//
//  Created by Copilot
//

import Foundation
import Vapor

@testable import Agent

/// A controller that mocks Google Gemini API responses
@MainActor
class GeminiChatController {
    private var mockResponses: [GeminiModelMessage]

    init() {
        self.mockResponses = []
    }

    /// Set mock responses to be returned in the streaming API
    /// - Parameter responses: List of model messages to be returned as chunks
    func mockChatResponse(_ responses: [GeminiModelMessage]) {
        mockResponses = responses
    }

    /// Register routes for this controller on a Vapor router
    /// - Parameter routes: The router to register routes on
    func registerRoutes(on routes: RoutesBuilder) {
        // Register the endpoint that matches Gemini's API
        // Pattern: /v1beta/models/{model}:streamGenerateContent
        let v1Routes = routes.grouped("v1beta")
        let modelsRoutes = v1Routes.grouped("models")
        modelsRoutes.post(":model", "streamGenerateContent", use: handleStreamGeneration)
    }

    private func handleStreamGeneration(request: Request) async throws -> Response {
        let body = Response.Body(stream: { writer in
            Task {
                let mockResponses = await self.mockResponses
                for response in mockResponses {
                    let geminiResponse = GeminiResponse(
                        candidates: [
                            GeminiResponse.Candidate(
                                content: GeminiContent(role: .model, parts: response.parts),
                                finishReason: nil
                            )
                        ]
                    )
                    let jsonData = try JSONEncoder().encode(geminiResponse)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
                    _ = writer.write(.buffer(ByteBuffer(string: "\(jsonString)\n")))
                }

                _ = writer.write(.end)
            }
        })

        let response = Response(status: .ok, body: body)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        return response
    }
}
