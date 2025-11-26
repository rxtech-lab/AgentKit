//
//  ChatProvider.swift
//  AgentLayout
//
//  Created by Qiwei Li on 11/26/25.
//

import Agent
import Foundation
import SwiftUI

// MARK: - Type-erased Encodable wrapper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self._encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

@Observable
@MainActor
public class ChatProvider: ChatProviderProtocol {

    // MARK: - Static Constants
    public static let REJECT_MESSAGE: LocalizedStringKey = "User cancelled this tool call"
    public static let REJECT_MESSAGE_STRING = "User cancelled this tool call"

    // MARK: - Observable State
    public private(set) var chat: Chat?
    public private(set) var status: ChatStatus = .idle

    // MARK: - Configuration
    public var systemPrompt: String?
    public var currentModel: Model?
    public var currentSource: Source?
    public private(set) var tools: [any AgentToolProtocol] = []

    // MARK: - Callbacks
    public var onSend: ((Message) -> Void)?
    public var onMessage: ((Message) -> Void)?
    public var onDelete: ((Int) -> Void)?
    public var onEdit: ((Int, Message) -> Void)?
    public var onMessageChange: (([Message]) -> Void)?

    // MARK: - Internal State (not observed)
    @ObservationIgnored private var agentClient = AgentClient()
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var currentStreamingMessageId: String?
    @ObservationIgnored private var isSetup = false

    // MARK: - Scroll Support (set by view)
    @ObservationIgnored public var scrollToBottom: (() -> Void)?

    // MARK: - Computed Properties

    public var messages: [Message] {
        chat?.messages ?? []
    }

    public var isWaitingForToolResult: Bool {
        guard let chat = chat else { return false }

        guard
            let lastAssistantIndex = chat.messages.lastIndex(where: {
                if case .openai(let m) = $0, case .assistant(let a) = m,
                    let tc = a.toolCalls, !tc.isEmpty
                {
                    return true
                }
                return false
            })
        else { return false }

        let assistantMsg = chat.messages[lastAssistantIndex]
        guard case .openai(let m) = assistantMsg,
            case .assistant(let a) = m,
            let toolCalls = a.toolCalls
        else { return false }

        let toolCallIds = Set(toolCalls.compactMap { $0.id })
        var resolvedIds = Set<String>()

        for i in (lastAssistantIndex + 1)..<chat.messages.count {
            if case .openai(let m) = chat.messages[i], case .tool(let t) = m {
                resolvedIds.insert(t.toolCallId)
            }
        }

        return !toolCallIds.isSubset(of: resolvedIds)
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    public func setup(
        chat: Chat,
        currentModel: Model,
        currentSource: Source,
        systemPrompt: String? = nil,
        tools: [any AgentToolProtocol] = [],
        onSend: ((Message) -> Void)? = nil,
        onMessage: ((Message) -> Void)? = nil,
        onDelete: ((Int) -> Void)? = nil,
        onEdit: ((Int, Message) -> Void)? = nil,
        onMessageChange: (([Message]) -> Void)? = nil
    ) {
        // Allow setup if not yet setup OR if chat ID changed (view was recreated)
        let shouldSetup = !isSetup || self.chat?.id != chat.id

        guard shouldSetup else {
            // Still update tools/systemPrompt even if chat is same
            self.tools = tools
            self.systemPrompt = systemPrompt
            return
        }

        self.chat = chat
        self.currentModel = currentModel
        self.currentSource = currentSource
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.onSend = onSend
        self.onMessage = onMessage
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onMessageChange = onMessageChange
        self.isSetup = true
    }

    // MARK: - Message Change Notification

    private func notifyMessageChange() {
        onMessageChange?(messages)
    }

    // MARK: - ChatProviderProtocol

    nonisolated public func sendMessage(message: String) async throws {
        // This is called internally by send() for external persistence hooks
        // Subclasses can override to persist messages to a database
    }

    nonisolated public func sendFunctionResult(id: String, result: any Encodable) async throws {
        // Encode the result to JSON string BEFORE entering MainActor context
        // to avoid sending non-Sendable `result` across actor boundaries
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let resultString: String
        if let data = try? encoder.encode(AnyEncodable(result)),
            let jsonString = String(data: data, encoding: .utf8)
        {
            resultString = jsonString
        } else {
            resultString = String(describing: result)
        }

        await MainActor.run {
            // Find the tool name from the pending tool call
            var toolName: String?
            if let chat = self.chat {
                for message in chat.messages.reversed() {
                    if case .openai(let openAIMsg) = message,
                        case .assistant(let assistant) = openAIMsg,
                        let toolCalls = assistant.toolCalls
                    {
                        if let toolCall = toolCalls.first(where: { $0.id == id }) {
                            toolName = toolCall.function?.name
                            break
                        }
                    }
                }
            }

            // Create and append the tool result message
            let toolMsg = Message.openai(
                .tool(.init(content: resultString, toolCallId: id, name: toolName))
            )
            self.chat?.messages.append(toolMsg)
            self.onMessage?(toolMsg)
            self.notifyMessageChange()

            // Check if all tool calls are resolved, then continue the conversation
            if !self.isWaitingForToolResult {
                self.continueConversationAfterToolResults()
            }
        }
    }

    nonisolated public func rejectFunction(id: String) async throws {
        await MainActor.run {
            // Create and append the rejection message
            let toolMsg = Message.openai(
                .tool(.init(content: Self.REJECT_MESSAGE_STRING, toolCallId: id))
            )
            self.chat?.messages.append(toolMsg)
            self.onMessage?(toolMsg)
            self.notifyMessageChange()
        }
    }

    // MARK: - Private Helper Methods

    private func continueConversationAfterToolResults() {
        guard generationTask == nil else { return }
        guard let currentSource = currentSource, let currentModel = currentModel else { return }

        let source = currentSource
        let model = currentModel

        generationTask = Task { [weak self] in
            guard let self = self else { return }
            self.status = .loading

            do {
                var messagesToSend = self.chat?.messages ?? []
                if let systemPrompt = self.systemPrompt, !systemPrompt.isEmpty {
                    let systemMessage = Message.openai(.system(.init(content: systemPrompt)))
                    messagesToSend.insert(systemMessage, at: 0)
                }

                let stream = await self.agentClient.process(
                    messages: messagesToSend,
                    model: model,
                    source: source,
                    tools: self.tools
                )

                var currentAssistantId = UUID().uuidString
                var currentAssistantContent = ""

                let initialMsg = Message.openai(
                    .assistant(
                        .init(
                            id: currentAssistantId,
                            content: "",
                            toolCalls: nil, audio: nil
                        )))
                self.chat?.messages.append(initialMsg)
                self.currentStreamingMessageId = currentAssistantId

                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { [weak self] in
                    self?.scrollToBottom?()
                }

                for try await part in stream {
                    if Task.isCancelled { break }

                    switch part {
                    case .textDelta(let text):
                        if self.currentStreamingMessageId == nil {
                            currentAssistantId = UUID().uuidString
                            currentAssistantContent = ""
                            let newMsg = Message.openai(
                                .assistant(
                                    .init(
                                        id: currentAssistantId,
                                        content: "",
                                        toolCalls: nil, audio: nil
                                    )))
                            self.chat?.messages.append(newMsg)
                            self.currentStreamingMessageId = currentAssistantId
                        }

                        currentAssistantContent += text
                        if let index = self.chat?.messages.firstIndex(where: {
                            $0.id == self.currentStreamingMessageId
                        }) {
                            self.chat?.messages[index] = Message.openai(
                                .assistant(
                                    .init(
                                        id: currentAssistantId,
                                        content: currentAssistantContent,
                                        toolCalls: nil, audio: nil
                                    )))
                        }

                    case .message(let msg):
                        var shouldScroll = false
                        if case .openai(let openAIMsg) = msg,
                            case .assistant = openAIMsg.role
                        {
                            if let index = self.chat?.messages.firstIndex(where: {
                                $0.id == self.currentStreamingMessageId
                            }) {
                                self.chat?.messages[index] = msg
                            } else {
                                self.chat?.messages.append(msg)
                                shouldScroll = true
                            }
                            currentAssistantContent = ""
                            currentAssistantId = UUID().uuidString
                            self.currentStreamingMessageId = nil
                        } else {
                            self.chat?.messages.append(msg)
                            shouldScroll = true
                        }

                        self.onMessage?(msg)
                        self.notifyMessageChange()

                        if shouldScroll {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await MainActor.run { [weak self] in
                                self?.scrollToBottom?()
                            }
                        }

                    case .error(let e):
                        print("Agent Error: \(e)")
                    }
                }
                self.status = .idle
                self.generationTask = nil
                self.currentStreamingMessageId = nil
            } catch {
                print("Error continuing conversation: \(error)")
                if let msgId = self.currentStreamingMessageId {
                    self.chat?.messages.removeAll { $0.id == msgId }
                    self.notifyMessageChange()
                }
                self.status = .idle
                self.generationTask = nil
                self.currentStreamingMessageId = nil
            }
        }
    }

    // MARK: - Public Methods

    public func send(_ message: String) {
        guard generationTask == nil else { return }
        guard var chat = chat, let currentSource = currentSource, let currentModel = currentModel
        else { return }

        let userMsg = Message.openai(.user(.init(content: message)))
        chat.messages.append(userMsg)
        self.chat = chat
        onSend?(userMsg)
        notifyMessageChange()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollToBottom?()
        }

        startGeneration(source: currentSource, model: currentModel, userMessage: message)
    }

    /// Internal method to start generation without adding a user message.
    /// Used by both `send` and `regenerate`.
    private func startGeneration(source: Source, model: Model, userMessage: String? = nil) {
        generationTask = Task { [weak self] in
            guard let self = self else { return }
            self.status = .loading

            if let message = userMessage {
                try? await self.sendMessage(message: message)
            }

            do {
                var messagesToSend = self.chat?.messages ?? []
                if let systemPrompt = self.systemPrompt, !systemPrompt.isEmpty {
                    let systemMessage = Message.openai(.system(.init(content: systemPrompt)))
                    messagesToSend.insert(systemMessage, at: 0)
                }

                let stream = await self.agentClient.process(
                    messages: messagesToSend,
                    model: model,
                    source: source,
                    tools: self.tools
                )

                var currentAssistantId = UUID().uuidString
                var currentAssistantContent = ""

                let initialMsg = Message.openai(
                    .assistant(
                        .init(
                            id: currentAssistantId,
                            content: "",
                            toolCalls: nil, audio: nil
                        )))
                self.chat?.messages.append(initialMsg)
                self.currentStreamingMessageId = currentAssistantId

                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run { [weak self] in
                    self?.scrollToBottom?()
                }

                for try await part in stream {
                    if Task.isCancelled { break }

                    switch part {
                    case .textDelta(let text):
                        if self.currentStreamingMessageId == nil {
                            currentAssistantId = UUID().uuidString
                            currentAssistantContent = ""
                            let newMsg = Message.openai(
                                .assistant(
                                    .init(
                                        id: currentAssistantId,
                                        content: "",
                                        toolCalls: nil, audio: nil
                                    )))
                            self.chat?.messages.append(newMsg)
                            self.currentStreamingMessageId = currentAssistantId
                        }

                        currentAssistantContent += text
                        if let index = self.chat?.messages.firstIndex(where: {
                            $0.id == self.currentStreamingMessageId
                        }) {
                            self.chat?.messages[index] = Message.openai(
                                .assistant(
                                    .init(
                                        id: currentAssistantId,
                                        content: currentAssistantContent,
                                        toolCalls: nil, audio: nil
                                    )))
                        }

                    case .message(let msg):
                        var shouldScroll = false
                        if case .openai(let openAIMsg) = msg,
                            case .assistant = openAIMsg.role
                        {
                            if let index = self.chat?.messages.firstIndex(where: {
                                $0.id == self.currentStreamingMessageId
                            }) {
                                self.chat?.messages[index] = msg
                            } else {
                                self.chat?.messages.append(msg)
                                shouldScroll = true
                            }
                            currentAssistantContent = ""
                            currentAssistantId = UUID().uuidString
                            self.currentStreamingMessageId = nil
                        } else {
                            self.chat?.messages.append(msg)
                            shouldScroll = true
                        }

                        self.onMessage?(msg)
                        self.notifyMessageChange()

                        if shouldScroll {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await MainActor.run { [weak self] in
                                self?.scrollToBottom?()
                            }
                        }

                    case .error(let e):
                        print("Agent Error: \(e)")
                    }
                }
                self.status = .idle
                self.generationTask = nil
                self.currentStreamingMessageId = nil
            } catch {
                print("Error sending message: \(error)")
                if let msgId = self.currentStreamingMessageId {
                    self.chat?.messages.removeAll { $0.id == msgId }
                    self.notifyMessageChange()
                }
                self.status = .idle
                self.generationTask = nil
                self.currentStreamingMessageId = nil
            }
        }
    }

    public func edit(messageId: String, newContent: String) {
        guard generationTask == nil else { return }
        guard let index = chat?.messages.firstIndex(where: { $0.id == messageId }) else { return }

        let newMessage = Message.openai(.user(.init(content: newContent)))
        onEdit?(index, newMessage)

        chat?.messages.removeSubrange(index...)
        notifyMessageChange()
        send(newContent)
    }

    public func regenerate(messageId: String) {
        guard generationTask == nil else { return }
        guard let chat = chat else { return }
        guard let index = chat.messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard let currentSource = currentSource, let currentModel = currentModel else { return }

        // Find the user message content before the target message
        var userMessageContent: String? = nil
        for i in stride(from: index - 1, through: 0, by: -1) {
            if case .openai(let openAIMsg) = chat.messages[i],
                case .user(let userMsg) = openAIMsg
            {
                userMessageContent = userMsg.content
                break
            }
        }

        guard userMessageContent != nil else { return }

        // Remove the target message and all subsequent messages
        self.chat?.messages.removeSubrange(index...)
        notifyMessageChange()

        // Start generation without adding a new user message
        startGeneration(source: currentSource, model: currentModel)
    }

    public func cancel() {
        if let task = generationTask {
            task.cancel()
            generationTask = nil
            status = .idle

            if let msgId = currentStreamingMessageId,
                let index = chat?.messages.firstIndex(where: { $0.id == msgId })
            {
                if let msg = chat?.messages[index] {
                    onMessage?(msg)
                }

                let userCancelMsg = Message.openai(.user(.init(content: "Cancelled")))
                chat?.messages.append(userCancelMsg)
                notifyMessageChange()
            }
            currentStreamingMessageId = nil
        } else if isWaitingForToolResult {
            guard let chat = chat else { return }

            if let lastAssistantIndex = chat.messages.lastIndex(where: {
                if case .openai(let m) = $0, case .assistant(let a) = m,
                    let tc = a.toolCalls, !tc.isEmpty
                {
                    return true
                }
                return false
            }) {
                let assistantMsg = chat.messages[lastAssistantIndex]
                if case .openai(let m) = assistantMsg,
                    case .assistant(let a) = m,
                    let toolCalls = a.toolCalls
                {
                    for toolCall in toolCalls {
                        let alreadyResolved = chat.messages.contains { msg in
                            if case .openai(let m) = msg, case .tool(let t) = m {
                                return t.toolCallId == toolCall.id
                            }
                            return false
                        }

                        if !alreadyResolved, let id = toolCall.id {
                            let toolMsg = Message.openai(
                                .tool(.init(content: Self.REJECT_MESSAGE_STRING, toolCallId: id)))
                            self.chat?.messages.append(toolMsg)
                            onMessage?(toolMsg)
                            notifyMessageChange()

                            Task {
                                try? await self.rejectFunction(id: id)
                            }
                        }
                    }
                }
            }
        }
    }

    public func deleteMessage(at index: Int) {
        onDelete?(index)
        chat?.messages.remove(at: index)
        notifyMessageChange()
    }

    public func getToolStatus(for message: Message, in messages: [Message]) -> ToolStatus {
        guard case .openai(let openAIMessage) = message,
            case .assistant(let assistantMessage) = openAIMessage,
            let toolCalls = assistantMessage.toolCalls,
            !toolCalls.isEmpty
        else { return .completed }

        let toolCallIds = Set(toolCalls.compactMap { $0.id })
        var resolvedIds = Set<String>()
        var rejected = false

        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return .waitingForResult
        }

        for j in (index + 1)..<messages.count {
            if case .openai(let nextMsg) = messages[j],
                case .tool(let toolMsg) = nextMsg
            {
                if toolCallIds.contains(toolMsg.toolCallId) {
                    resolvedIds.insert(toolMsg.toolCallId)
                    if toolMsg.content == Self.REJECT_MESSAGE_STRING {
                        rejected = true
                    }
                }
            }
        }

        if toolCallIds.isSubset(of: resolvedIds) {
            return rejected ? .rejected : .completed
        } else {
            return .waitingForResult
        }
    }

    // MARK: - Updates

    public func updateChat(_ newChat: Chat) {
        self.chat = newChat
    }

    public func updateTools(_ newTools: [any AgentToolProtocol]) {
        self.tools = newTools
    }

    public func updateSystemPrompt(_ newSystemPrompt: String?) {
        self.systemPrompt = newSystemPrompt
    }

    /**
        Regenerates the conversation starting at the given message.
        This will remove all messages after the given message and regenerate the conversation from the given message.
        - Parameter message: The message to start regenerating from.
    */
    public func regenerate(startsAt message: Message) async throws {

    }
}
