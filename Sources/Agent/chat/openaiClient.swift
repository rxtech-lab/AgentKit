//
//  openai.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

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

class OpenAIClient {
    private let apiKey: String
    private let baseURL: URL
    var history: [Message] = []

    init(baseURL: URL, apiKey: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    @MainActor
    func generateStreamResponse(systemText: String, prompt: String, model: OpenAICompatibleModel)
        -> AsyncThrowingStream<Message, Error>
    {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpoint = "\(baseURL)/chat/completions"
                    guard let url = URL(string: endpoint) else {
                        throw OpenAIError.invalidURL
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                    var messages: [[String: Any]] = []
                    messages.append(["role": "system", "content": systemText])
                    //                    messages.append(contentsOf: history.map { ["role": $0.role.rawValue, "content": $0.content] })
                    messages.append(["role": "user", "content": prompt])

                    let requestBody: [String: Any] = [
                        //                        "model": model.rawValue,
                        "messages": messages,
                        "stream": true,
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    let (responseStream, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        let textResponse = response.description
                        throw OpenAIError.invalidResponse(url: url, textResponse: textResponse)
                    }

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
                                OpenAIAssistantMessage.self, from: delta)
                            if let content = decoded.content {
                                total += content
                                continuation.yield(
                                    Message.openai(
                                        .assistant(.init(content: total, toolCalls: [], audio: nil))
                                    ))
                            }

                            if let toolCalls = decoded.toolCalls {
                                totalToolCalls.append(contentsOf: toolCalls)
                                continuation.yield(
                                    Message.openai(
                                        .assistant(
                                            .init(
                                                content: nil, toolCalls: toolCalls, audio: nil
                                            )
                                        )
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
