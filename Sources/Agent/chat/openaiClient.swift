//
//  openai.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Combine
import Foundation

enum OpenAIError: LocalizedError {
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

struct OpenAIRequest: Codable {
    struct FunctionTool: Codable {
        let type: String
        let function: OpenAITool
    }

    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let tools: [FunctionTool]
    let reasoning: ReasoningConfig?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encode(tools, forKey: .tools)
        // Only encode reasoning if it's not nil
        if let reasoning = reasoning {
            try container.encode(reasoning, forKey: .reasoning)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools, reasoning
    }
}

struct StreamChunk: Codable {
    let id: String
    let created: Int
    let model: String
    let choices: [StreamChoice]
}

/// A single choice in a streaming response
struct StreamChoice: Codable {
    let index: Int
    let delta: OpenAIAssistantMessage
    let finishReason: String?
}

/// A streaming delta with its associated finish reason
struct StreamDelta: Sendable {
    let delta: OpenAIAssistantMessage
    let finishReason: String?
}

public actor OpenAIClient: ChatClient {
    private let apiKey: String
    private let baseURL: URL

    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    public init(apiKey: String, baseURL: URL? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
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
            throw OpenAIError.invalidResponse(url: endpoint, textResponse: errorBody)
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

    func generateStreamResponse(
        systemText: String, message: OpenAIUserMessage, model: OpenAICompatibleModel,
        tools: [OpenAITool] = [], history: [OpenAIMessage] = []
    )
        -> (stream: AsyncThrowingStream<OpenAIMessage, Error>, cancellable: Cancellable)
    {
        let task = Task<Void, Never> {}
        let stream = AsyncThrowingStream<OpenAIMessage, Error> { continuation in
            Task {
                do {
                    var messages: [OpenAIMessage] = []
                    messages.append(.system(.init(content: systemText)))
                    messages.append(contentsOf: history)
                    messages.append(.user(message))

                    let requestBody = OpenAIRequest(
                        model: model.id,
                        messages: messages,
                        stream: true,
                        tools: tools.map {
                            OpenAIRequest.FunctionTool(type: "function", function: $0)
                        },
                        reasoning: model.reasoningConfig
                    )

                    let responseStream = try await makeRequest(body: requestBody)
                    var total = ""
                    var totalToolCalls: [OpenAIToolCall] = []

                    for try await line in responseStream.lines {
                        if task.isCancelled {
                            continuation.finish()
                            break
                        }

                        if line.hasPrefix("data: "),
                            let data = line.dropFirst(6).data(using: .utf8),
                            let json = try? JSONDecoder().decode(StreamChunk.self, from: data),
                            let delta = json.choices.first?.delta
                        {
                            if let content = delta.content {
                                total += content
                                continuation.yield(
                                    .assistant(.init(content: total, toolCalls: [], audio: nil))
                                )
                            }

                            if let toolCalls = delta.toolCalls {
                                totalToolCalls.append(contentsOf: toolCalls)
                                continuation.yield(
                                    .assistant(
                                        .init(content: nil, toolCalls: toolCalls, audio: nil))
                                )
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return (stream, Cancellable { task.cancel() })
    }
}
