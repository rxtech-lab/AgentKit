import Foundation

/// Shared processing logic for OpenAI-compatible chat clients
struct OpenAIChatProcessor {
    /// Process a tool call and return its result as a JSON string
    static func processToolCall(
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

    /// Update messages with turn information
    /// If a system message exists, appends turn info to it. Otherwise, prepends a new system message.
    static func updateMessagesWithTurnInfo(
        _ messages: [OpenAIMessage],
        currentTurn: Int,
        maxTurns: Int
    ) -> [OpenAIMessage] {
        var updatedMessages = messages
        let turnInfo = "You are on turn \(currentTurn) of \(maxTurns). You have \(maxTurns - currentTurn) turns remaining."

        // Find existing system message
        if let systemIndex = updatedMessages.firstIndex(where: { $0.role == .system }) {
            // Update existing system message
            if case .system(let systemMsg) = updatedMessages[systemIndex] {
                let newContent = systemMsg.content + "\n\n" + turnInfo
                updatedMessages[systemIndex] = .system(.init(id: systemMsg.id, content: newContent))
            }
        } else {
            // Prepend new system message
            updatedMessages.insert(.system(.init(content: turnInfo)), at: 0)
        }

        return updatedMessages
    }

    /// Main processing logic that handles multi-turn conversations with tool calls
    static func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol],
        maxTurns: Int,
        streamChat: @escaping @Sendable ([OpenAIMessage], String, [OpenAITool], ReasoningConfig?) async -> AsyncThrowingStream<StreamDelta, Error>
    ) -> AsyncThrowingStream<AgentResponsePart, Error> {
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                var currentMessages: [OpenAIMessage] = messages.compactMap { msg in
                    if case .openai(let m) = msg { return m }
                    return nil
                }

                var keepGoing = true
                var currentTurn = 0

                while keepGoing {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    // Increment turn counter and check limit
                    currentTurn += 1
                    if currentTurn > maxTurns {
                        continuation.yield(.error(NSError(
                            domain: "AgentError",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Maximum turns (\(maxTurns)) exceeded"]
                        )))
                        continuation.finish()
                        return
                    }

                    // Update messages with turn information
                    let messagesWithTurnInfo = updateMessagesWithTurnInfo(
                        currentMessages,
                        currentTurn: currentTurn,
                        maxTurns: maxTurns
                    )

                    let openAITools = tools.map {
                        OpenAITool(
                            name: $0.name, description: $0.description, parameters: $0.parameters)
                    }

                    var currentAssistantContent = ""
                    var currentAssistantReasoning: String? = nil
                    var currentReasoningDetails: [OpenAIAssistantMessage.ReasoningDetail] = []
                    var accumulatedToolCalls:
                        [Int: (
                            id: String?, type: OpenAIToolCall.ToolType?, name: String?,
                            arguments: String, thoughtSignature: String?
                        )] = [:]

                    do {
                        let stream = await streamChat(
                            messagesWithTurnInfo,
                            model.id,
                            openAITools,
                            model.reasoningConfig
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

                            if let reasoningDetails = delta.reasoningDetails {
                                currentReasoningDetails.append(contentsOf: reasoningDetails)
                            }

                            if let toolCalls = delta.toolCalls {
                                hasToolCalls = true
                                for toolCall in toolCalls {
                                    let index = toolCall.index ?? 0
                                    var current = accumulatedToolCalls[index] ?? (nil, nil, nil, "", nil)

                                    if let id = toolCall.id { current.id = id }
                                    if let type = toolCall.type { current.type = type }
                                    if let function = toolCall.function {
                                        if let name = function.name { current.name = name }
                                        if let args = function.arguments {
                                            current.arguments += args
                                        }
                                        if let thoughtSig = function.thoughtSignature {
                                            current.thoughtSignature = thoughtSig
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
                                            function: .init(
                                                name: name,
                                                arguments: acc.arguments,
                                                thoughtSignature: acc.thoughtSignature
                                            )
                                        ))
                                }
                            }
                        }

                        let assistantMessage = OpenAIAssistantMessage(
                            content: currentAssistantContent.isEmpty
                                ? nil : currentAssistantContent,
                            toolCalls: finalToolCalls.isEmpty ? nil : finalToolCalls,
                            audio: nil,
                            reasoning: currentAssistantReasoning,
                            reasoningDetails: currentReasoningDetails.isEmpty ? nil : currentReasoningDetails
                        )

                        currentMessages.append(.assistant(assistantMessage))
                        continuation.yield(.message(.openai(.assistant(assistantMessage))))

                        // Updated stop condition logic
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
                                // No UI tools - execute all tools and continue regardless of finish_reason
                                toolsToExecute = finalToolCalls
                                keepGoing = true
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
                                                    let result = try await processToolCall(
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
                            // No tool calls - stop on finish_reason="stop" or if response is complete
                            if finalFinishReason == "stop" {
                                keepGoing = false
                            } else if finalFinishReason == nil || finalFinishReason == "length" || finalFinishReason == "content_filter" {
                                // These indicate the model is done, even without explicit "stop"
                                keepGoing = false
                            }
                            // Otherwise continue (will be caught by turn limit)
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
