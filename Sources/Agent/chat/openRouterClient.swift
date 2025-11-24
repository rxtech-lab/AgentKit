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
                            tools: openAITools
                        )

                        var hasToolCalls = false

                        for try await delta in stream {
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

                        if finalToolCalls.isEmpty {
                            keepGoing = false
                        } else {
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
        tools: [OpenAITool] = []
    ) -> AsyncThrowingStream<OpenAIAssistantMessage, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let requestBody = OpenAIRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        tools: tools.map {
                            OpenAIRequest.FunctionTool(type: "function", function: $0)
                        }
                    )

                    let responseStream = try await makeRequest(body: requestBody)

                    for try await line in responseStream.lines {
                        if line.hasPrefix("data: "),
                            let data = line.dropFirst(6).data(using: .utf8)
                        {
                            if let json = try? JSONDecoder().decode(StreamChunk.self, from: data),
                                let delta = json.choices.first?.delta
                            {
                                continuation.yield(delta)
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
