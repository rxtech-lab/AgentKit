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

    private func processToolCall(
        tool: any AgentToolProtocol,
        toolCall: OpenAIToolCall
    ) async throws -> String {
        let argumentsString = toolCall.function?.arguments ?? "{}"
        guard let data = argumentsString.data(using: .utf8) else {
            throw ToolError.invalidArgsEncoding
        }

        let output = try await tool.invoke(argsData: data, originalArgs: argumentsString)
        let outputData = try JSONEncoder().encode(output)
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    nonisolated public func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol]
    ) -> AsyncThrowingStream<AgentResponsePart, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var currentMessages: [OpenAIMessage] = messages.compactMap { msg in
                    if case .openai(let m) = msg { return m }
                    return nil
                }

                var keepGoing = true

                while keepGoing {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    let openAITools = tools.map {
                        OpenAITool(
                            name: $0.name, description: $0.description, parameters: $0.parameters)
                    }

                    var currentAssistantContent = ""
                    var currentAssistantReasoning: String? = nil
                    var accumulatedToolCalls:
                        [Int: (
                            id: String?, type: OpenAIToolCall.ToolType?, name: String?,
                            arguments: String
                        )] = [:]

                    do {
                        let stream = await self.streamChat(
                            messages: currentMessages,
                            model: model.id,
                            tools: openAITools,
                            reasoning: model.reasoningConfig
                        )

                        var hasToolCalls = false
                        var finalFinishReason: String? = nil

                        for try await streamDelta in stream {
                            let delta = streamDelta.delta

                            // Capture finish_reason from the final chunk
                            if let finishReason = streamDelta.finishReason {
                                finalFinishReason = finishReason
                            }

                            if let content = delta.content {
                                currentAssistantContent += content
                                continuation.yield(.textDelta(content))
                            }

                            if let reasoning = delta.reasoning {
                                if currentAssistantReasoning == nil {
                                    currentAssistantReasoning = ""
                                }
                                currentAssistantReasoning! += reasoning
                            }

                            if let toolCalls = delta.toolCalls {
                                hasToolCalls = true
                                for toolCall in toolCalls {
                                    let index = toolCall.index ?? 0
                                    var current = accumulatedToolCalls[index] ?? (nil, nil, nil, "")

                                    if let id = toolCall.id { current.id = id }
                                    if let type = toolCall.type { current.type = type }
                                    if let function = toolCall.function {
                                        if let name = function.name { current.name = name }
                                        if let args = function.arguments {
                                            current.arguments += args
                                        }
                                    }
                                    accumulatedToolCalls[index] = current
                                }
                            }
                        }

                        // Turn finished
                        var finalToolCalls: [OpenAIToolCall] = []
                        if hasToolCalls {
                            let sortedIndices = accumulatedToolCalls.keys.sorted()
                            for index in sortedIndices {
                                if let acc = accumulatedToolCalls[index],
                                    let id = acc.id,
                                    let type = acc.type,
                                    let name = acc.name
                                {
                                    finalToolCalls.append(
                                        OpenAIToolCall(
                                            index: index,
                                            id: id,
                                            type: type,
                                            function: .init(name: name, arguments: acc.arguments)
                                        ))
                                }
                            }
                        }

                        let assistantMessage = OpenAIAssistantMessage(
                            content: currentAssistantContent.isEmpty
                                ? nil : currentAssistantContent,
                            toolCalls: finalToolCalls.isEmpty ? nil : finalToolCalls,
                            audio: nil,
                            reasoning: currentAssistantReasoning
                        )

                        currentMessages.append(.assistant(assistantMessage))
                        continuation.yield(.message(.openai(.assistant(assistantMessage))))

                        // Use finish_reason to determine loop control
                        // Check for tool calls first, regardless of finish_reason
                        if !finalToolCalls.isEmpty {
                            // Check for UI tools
                            let hasUITool = finalToolCalls.contains { call in
                                guard let name = call.function?.name else { return false }
                                return tools.contains { $0.name == name && $0.toolType == .ui }
                            }

                            // Determine which tools to execute automatically
                            let toolsToExecute: [OpenAIToolCall]
                            if hasUITool {
                                keepGoing = false
                                toolsToExecute = finalToolCalls.filter { call in
                                    guard let name = call.function?.name else { return true }
                                    return !tools.contains { $0.name == name && $0.toolType == .ui }
                                }
                            } else {
                                toolsToExecute = finalToolCalls
                            }

                            if !toolsToExecute.isEmpty {
                                // Parallel execution
                                await withTaskGroup(of: OpenAIMessage?.self) { group in
                                    for toolCall in toolsToExecute {
                                        group.addTask {
                                            guard let function = toolCall.function,
                                                let name = function.name,
                                                function.arguments != nil,
                                                let id = toolCall.id
                                            else { return nil }

                                            if let tool = tools.first(where: { $0.name == name }) {
                                                do {
                                                    let result = try await self.processToolCall(
                                                        tool: tool, toolCall: toolCall)
                                                    return .tool(
                                                        .init(
                                                            content: result, toolCallId: id,
                                                            name: name))
                                                } catch let error as ToolError {
                                                    switch error {
                                                    case .invalidToolArgs:
                                                        return .tool(
                                                            .init(
                                                                content:
                                                                    "Error: \(error.localizedDescription). Please fix the arguments and try again.",
                                                                toolCallId: id, name: name))
                                                    default:
                                                        return .tool(
                                                            .init(
                                                                content:
                                                                    "Error: \(error.localizedDescription)",
                                                                toolCallId: id, name: name))
                                                    }
                                                } catch {
                                                    return .tool(
                                                        .init(
                                                            content:
                                                                "Error: \(error.localizedDescription)",
                                                            toolCallId: id, name: name))
                                                }
                                            } else {
                                                return .tool(
                                                    .init(
                                                        content: "Tool \(name) not found.",
                                                        toolCallId: id, name: name))
                                            }
                                        }
                                    }

                                    for await result in group {
                                        if let msg = result {
                                            currentMessages.append(msg)
                                            continuation.yield(.message(.openai(msg)))
                                        }
                                    }
                                }
                            }
                        } else {
                            // No tool calls - check finish_reason to determine if we should stop
                            if finalFinishReason == "stop" || finalFinishReason == nil || finalFinishReason == "length" || finalFinishReason == "content_filter" {
                                // Stop conditions: normal completion, no reason, length limit, or content filter
                                keepGoing = false
                            } else {
                                // Unknown finish_reason without tool calls - stop
                                keepGoing = false
                            }
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
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
