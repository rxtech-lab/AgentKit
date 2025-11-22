import Combine
import Foundation

public enum AgentResponsePart: Sendable {
    case textDelta(String)
    case message(Message)
    case error(Error)
}

public actor AgentClient {
    public enum ToolError: Error, LocalizedError {
        case invalidToolArgs(toolName: String, args: String, underlyingError: Error)
        case invalidArgsEncoding

        public var errorDescription: String? {
            switch self {
            case .invalidToolArgs(let toolName, _, let underlyingError):
                return
                    "Invalid arguments for tool '\(toolName)': \(underlyingError.localizedDescription)"
            case .invalidArgsEncoding:
                return "Invalid arguments encoding"
            }
        }
    }

    public init() {}

    private func processToolCall(
        tool: any AgentToolProtocol,
        toolCall: OpenAIToolCall
    ) async throws -> String {
        let argumentsString = toolCall.function?.arguments ?? "{}"
        guard let data = argumentsString.data(using: .utf8) else {
            throw ToolError.invalidArgsEncoding
        }

        // Verify arguments can be decoded to the tool's input type
        do {
            _ = try JSONDecoder().decode(tool.inputType, from: data)
        } catch {
            throw ToolError.invalidToolArgs(
                toolName: tool.name, args: argumentsString, underlyingError: error)
        }

        return try await tool.invoke(argumentsString)
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
                            audio: nil
                        )

                        currentMessages.append(.assistant(assistantMessage))
                        continuation.yield(.message(.openai(.assistant(assistantMessage))))

                        if finalToolCalls.isEmpty {
                            keepGoing = false
                        } else {
                            // Parallel execution
                            await withTaskGroup(of: OpenAIMessage?.self) { group in
                                for toolCall in finalToolCalls {
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
                                                return .tool(.init(content: result, toolCallId: id))
                                            } catch let error as ToolError {
                                                switch error {
                                                case .invalidToolArgs:
                                                    return .tool(
                                                        .init(
                                                            content:
                                                                "Error: \(error.localizedDescription). Please fix the arguments and try again.",
                                                            toolCallId: id))
                                                default:
                                                    return .tool(
                                                        .init(
                                                            content:
                                                                "Error: \(error.localizedDescription)",
                                                            toolCallId: id))
                                                }
                                            } catch {
                                                return .tool(
                                                    .init(
                                                        content:
                                                            "Error: \(error.localizedDescription)",
                                                        toolCallId: id))
                                            }
                                        } else {
                                            return .tool(
                                                .init(
                                                    content: "Tool \(name) not found.",
                                                    toolCallId: id))
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
