//
//  openRouterClient.swift
//  AgentLayout
//
//  Created by Claude on 11/24/25.
//

import Combine
import Foundation

enum OpenRouterError: LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(url: URL, textResponse: String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse(let url, let textResponse):
            return "Invalid response from server.\n URL: \(url)\n Response: \(textResponse)"
        case .decodingError:
            return "Failed to decode response."
        }
    }
}

public actor OpenRouterClient: ChatClient {
    private let apiKey: String
    private let baseURL: URL
    private let appName: String?
    private let siteURL: String?

    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    public init(
        apiKey: String,
        baseURL: URL? = nil,
        appName: String? = nil,
        siteURL: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.appName = appName
        self.siteURL = siteURL
    }

    nonisolated public func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol],
        maxTurns: Int = 20
    ) -> AsyncThrowingStream<AgentResponsePart, Error> {
        return OpenAIChatProcessor.process(
            messages: messages,
            model: model,
            tools: tools,
            maxTurns: maxTurns,
            streamChat: { [self] messages, modelId, tools, reasoning in
                await self.streamChat(
                    messages: messages,
                    model: modelId,
                    tools: tools,
                    reasoning: reasoning
                )
            }
        )
    }

    func makeRequest(
        body: OpenAIRequest
    ) async throws -> URLSession.AsyncBytes {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenRouter-specific headers
        if let siteURL = siteURL {
            request.addValue(siteURL, forHTTPHeaderField: "HTTP-Referer")
        }
        if let appName = appName {
            request.addValue(appName, forHTTPHeaderField: "X-Title")
        }

        request.httpBody = try JSONEncoder().encode(body)

        let (responseStream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            // Read the full error body from responseStream
            var errorBody = ""
            for try await line in responseStream.lines {
                errorBody += line
            }
            throw OpenRouterError.invalidResponse(url: endpoint, textResponse: errorBody)
        }

        return responseStream
    }

    func streamChat(
        messages: [OpenAIMessage],
        model: String,
        tools: [OpenAITool] = [],
        reasoning: ReasoningConfig? = nil
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let requestBody = OpenAIRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        tools: tools.map {
                            OpenAIRequest.FunctionTool(type: "function", function: $0)
                        },
                        reasoning: reasoning
                    )

                    let responseStream = try await makeRequest(body: requestBody)

                    for try await line in responseStream.lines {
                        if line.hasPrefix("data: "),
                            let data = line.dropFirst(6).data(using: .utf8)
                        {
                            if let json = try? JSONDecoder().decode(StreamChunk.self, from: data),
                                let choice = json.choices.first
                            {
                                continuation.yield(StreamDelta(
                                    delta: choice.delta,
                                    finishReason: choice.finishReason
                                ))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
