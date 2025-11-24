import Combine
import Foundation

public enum AgentResponsePart: Sendable {
    case textDelta(String)
    case message(Message)
    case error(Error)
}

public actor AgentClient {
    public init() {}

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

    public func process(
        messages: [Message],
        model: String,
        tools: [any AgentToolProtocol],
        source: Source
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

                    guard let baseURL = URL(string: source.endpoint) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    let client = OpenAIClient(
                        baseURL: baseURL, apiKey: source.apiKey)
                    let openAITools = tools.map {
                        OpenAITool(
                            name: $0.name, description: $0.description, parameters: $0.parameters)
                    }

                    var currentAssistantContent = ""
                    var currentAssistantReasoning: String? = nil
                    // Accumulate tool calls: index -> (id, type, name, arguments)
                    var accumulatedToolCalls:
                        [Int: (
                            id: String?, type: OpenAIToolCall.ToolType?, name: String?,
                            arguments: String
                        )] = [:]

                    do {
                        let stream = await client.streamChat(
                            messages: currentMessages,
                            model: model,
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
}
