//
//  openai.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Alamofire
import Combine
import Foundation
import KeyValueCoder

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

actor OpenAIClient {
    private let apiKey: String
    private let baseURL: URL

    init(baseURL: URL, apiKey: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func makeRequest(
        body: [String: Any]
    ) async throws -> URLSession.AsyncBytes {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseStream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let textResponse = response.description
            throw OpenAIError.invalidResponse(url: endpoint, textResponse: textResponse)
        }

        return responseStream
    }

    func generateStreamResponse(
        systemText: String, message: OpenAIUserMessage, model: OpenAICompatibleModel,
        tools: [OpenAITool] = [], history: [OpenAIMessage] = []
    )
        -> AsyncThrowingStream<OpenAIMessage, Error>
    {

        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [OpenAIMessage] = []
                    messages.append(.system(.init(content: systemText)))
                    messages.append(contentsOf: history)
                    messages.append(.user(message))

                    let requestBody: [String: Any] = [
                        "model": model.id
                            // "messages": messages,
                            // "stream": true,
                            // "tools": tools,
                    ]

                    let responseStream = try await makeRequest(body: requestBody)
                    var total = ""
                    var totalToolCalls: [OpenAIToolCall] = []
                    for try await line in responseStream.lines {
                        if line.hasPrefix("data: "),
                            let data = line.dropFirst(6).data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data)
                                as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let delta = choices.first?["delta"] as? [String: Any]
                        {
                            let decoded = try KeyValueDecoder().decode(
                                OpenAIAssistantMessage.self, from: delta
                            )
                            if let content = decoded.content {
                                total += content
                                continuation.yield(
                                    .assistant(.init(content: total, toolCalls: [], audio: nil))
                                )
                            }

                            if let toolCalls = decoded.toolCalls {
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
    }
}
