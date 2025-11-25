//
//  ChatListView.swift
//  chess-master-ultimate
//
//  Created by Qiwei Li on 5/17/25.
//

import Agent
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct InputHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ViewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct AgentLayout: View {
    public static let REJECT_MESSAGE = "User cancelled this tool call"

    @State var chat: Chat

    private let initialChat: Chat
    @State private var newMessage: String = ""
    @State private var error: Error? = nil
    @State private var showAlert: Bool = false
    @State private var status: ChatStatus = .idle
    @State private var inputHeight: CGFloat = 80
    @State private var agentClient = AgentClient()
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var currentStreamingMessageId: String? = nil
    @State private var isAtBottom: Bool = true
    @State private var scrollViewHeight: CGFloat = 0

    @Binding var currentModel: Model
    @Binding var currentSource: Source
    let sources: [Source]

    let chatProvider: ChatProvider?
    let renderMessage: MessageRenderer?
    let onSend: ((Message) -> Void)?
    let onMessage: ((Message) -> Void)?
    let onDelete: ((Int) -> Void)?
    let onEdit: ((Int, Message) -> Void)?
    let tools: [any AgentToolProtocol]
    let systemPrompt: String?

    public init(
        systemPrompt: String? = nil,
        chat: Chat,
        currentModel: Binding<Model>,
        currentSource: Binding<Source>,
        sources: [Source],
        chatProvider: ChatProvider? = nil,
        renderMessage: MessageRenderer? = nil,
        onSend: ((Message) -> Void)? = nil,
        onMessage: ((Message) -> Void)? = nil,
        onDelete: ((Int) -> Void)? = nil,
        onEdit: ((Int, Message) -> Void)? = nil,
        tools: [any AgentToolProtocol] = []
    ) {
        self._chat = .init(initialValue: chat)
        self.initialChat = chat
        self._currentModel = currentModel
        self._currentSource = currentSource
        self.sources = sources
        self.chatProvider = chatProvider
        self.renderMessage = renderMessage
        self.onSend = onSend
        self.onMessage = onMessage
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.tools = tools
        self.systemPrompt = systemPrompt
    }

    // MARK: - Private Methods

    private var isWaitingForToolResult: Bool {
        // Find last assistant message with tools
        guard
            let lastAssistantIndex = chat.messages.lastIndex(where: {
                if case .openai(let m) = $0, case .assistant(let a) = m, let tc = a.toolCalls,
                    !tc.isEmpty
                {
                    return true
                }
                return false
            })
        else {
            return false
        }

        let assistantMsg = chat.messages[lastAssistantIndex]
        guard case .openai(let m) = assistantMsg, case .assistant(let a) = m,
            let toolCalls = a.toolCalls
        else { return false }

        let toolCallIds = Set(toolCalls.compactMap { $0.id })

        // Check subsequent messages for resolution
        var resolvedIds = Set<String>()
        for i in (lastAssistantIndex + 1)..<chat.messages.count {
            if case .openai(let m) = chat.messages[i], case .tool(let t) = m {
                resolvedIds.insert(t.toolCallId)
            }
        }

        return !toolCallIds.isSubset(of: resolvedIds)
    }

    private func getToolStatus(for message: Message, in messages: [Message]) -> ToolStatus {
        guard case .openai(let openAIMessage) = message,
            case .assistant(let assistantMessage) = openAIMessage,
            let toolCalls = assistantMessage.toolCalls,
            !toolCalls.isEmpty
        else {
            return .completed
        }

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
                    if toolMsg.content == Self.REJECT_MESSAGE {
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

    private func scrollToBottom() {
        guard let lastMessage = chat.messages.last else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .top)
        }
    }

    private func sendMessage(_ message: String) {
        // Guard against concurrent generation
        guard generationTask == nil else { return }

        // Create and append user message
        let userMsg = Message.openai(.user(.init(content: message)))
        chat.messages.append(userMsg)

        // Notify external handler if exists
        if let onSend = onSend {
            onSend(userMsg)
        }

        // Scroll to bottom after sending
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollToBottom()
        }

        let source = currentSource
        generationTask = Task {
            status = .loading

            // Notify chatProvider if exists (persistence)
            if let chatProvider = chatProvider {
                try? await chatProvider.sendMessage(
                    message: message, model: currentModel
                )
            }

            do {
                // Prepend system message if systemPrompt is provided
                var messagesToSend = chat.messages
                if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                    let systemMessage = Message.openai(.system(.init(content: systemPrompt)))
                    messagesToSend.insert(systemMessage, at: 0)
                }

                let stream = await agentClient.process(
                    messages: messagesToSend,
                    model: currentModel,
                    source: source,
                    tools: tools
                )

                var currentAssistantId = UUID().uuidString
                var currentAssistantContent = ""

                // Add empty assistant message immediately
                let initialMsg = Message.openai(
                    .assistant(
                        .init(
                            id: currentAssistantId,
                            content: "",
                            toolCalls: nil, audio: nil
                        )))
                chat.messages.append(initialMsg)
                currentStreamingMessageId = currentAssistantId

                // Scroll to show the new message
                try? await Task.sleep(nanoseconds: 100_000_000)
                await MainActor.run {
                    scrollToBottom()
                }

                for try await part in stream {
                    // Check for cancellation
                    if Task.isCancelled {
                        break
                    }

                    switch part {
                    case .textDelta(let text):
                        // If no streaming message exists, create one for multi-turn conversations
                        if currentStreamingMessageId == nil {
                            currentAssistantId = UUID().uuidString
                            currentAssistantContent = ""
                            let newMsg = Message.openai(
                                .assistant(
                                    .init(
                                        id: currentAssistantId,
                                        content: "",
                                        toolCalls: nil, audio: nil
                                    )))
                            chat.messages.append(newMsg)
                            currentStreamingMessageId = currentAssistantId
                        }

                        currentAssistantContent += text
                        // Update message by ID
                        if let index = chat.messages.firstIndex(where: {
                            $0.id == currentStreamingMessageId
                        }) {
                            chat.messages[index] = Message.openai(
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
                            // Update message by ID
                            if let index = chat.messages.firstIndex(where: {
                                $0.id == currentStreamingMessageId
                            }) {
                                chat.messages[index] = msg
                            } else {
                                // Append as new message if no streaming message to update
                                // This handles subsequent assistant messages in multi-turn conversations
                                chat.messages.append(msg)
                                shouldScroll = true
                            }
                            // Prepare for next turn
                            currentAssistantContent = ""
                            currentAssistantId = UUID().uuidString
                            currentStreamingMessageId = nil
                        } else {
                            chat.messages.append(msg)
                            shouldScroll = true
                        }

                        // Invoke callback for AI replies and tool results
                        onMessage?(msg)

                        // Scroll to bottom on message receive
                        if shouldScroll {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await MainActor.run {
                                scrollToBottom()
                            }
                        }
                    case .error(let e):
                        print("Agent Error: \(e)")
                        self.error = e
                        self.showAlert = true
                    }
                }
                status = .idle
                generationTask = nil
                currentStreamingMessageId = nil
            } catch {
                print("Error sending message: \(error)")
                // Remove the empty assistant message on error
                if let msgId = currentStreamingMessageId {
                    chat.messages.removeAll { $0.id == msgId }
                }
                self.error = error
                self.showAlert = true
                status = .idle
                generationTask = nil
                currentStreamingMessageId = nil
            }
        }
    }

    private func handleEdit(messageId: String, newContent: String) {
        // Guard against concurrent generation
        guard generationTask == nil else { return }

        // Find the index of the message being edited
        guard let index = chat.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        // Create the new user message
        let newMessage = Message.openai(.user(.init(content: newContent)))

        // Notify external handler if exists
        onEdit?(index, newMessage)

        // Remove all messages after and including the edited message
        chat.messages.removeSubrange(index...)

        // Send the edited message
        sendMessage(newContent)
    }

    private func handleRegenerate(messageId: String) {
        // Guard against concurrent generation
        guard generationTask == nil else { return }

        // Find the index of the assistant message
        guard let index = chat.messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        // Find the previous user message
        var userMessageContent: String? = nil
        for i in stride(from: index - 1, through: 0, by: -1) {
            if case .openai(let openAIMsg) = chat.messages[i],
                case .user(let userMsg) = openAIMsg
            {
                userMessageContent = userMsg.content
                break
            }
        }

        guard let content = userMessageContent else {
            return
        }

        // Remove messages from the assistant message onwards
        chat.messages.removeSubrange(index...)

        // Re-send the user message
        sendMessage(content)
    }

    private func handleCancel() {
        if let task = generationTask {
            task.cancel()
            generationTask = nil
            status = .idle

            // Emit onMessage callback with partial content
            if let msgId = currentStreamingMessageId,
                let index = chat.messages.firstIndex(where: { $0.id == msgId })
            {
                onMessage?(chat.messages[index])

                // Append "Cancelled" user message
                let userCancelMsg = Message.openai(.user(.init(content: "Cancelled")))
                chat.messages.append(userCancelMsg)
            }
            currentStreamingMessageId = nil
        } else if isWaitingForToolResult {
            // User cancelled tool call
            if let lastAssistantIndex = chat.messages.lastIndex(where: {
                if case .openai(let m) = $0, case .assistant(let a) = m, let tc = a.toolCalls,
                    !tc.isEmpty
                {
                    return true
                }
                return false
            }) {
                let assistantMsg = chat.messages[lastAssistantIndex]
                if case .openai(let m) = assistantMsg, case .assistant(let a) = m,
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
                                .tool(.init(content: Self.REJECT_MESSAGE, toolCallId: id)))
                            chat.messages.append(toolMsg)

                            // Invoke onMessage callback for the rejection message
                            onMessage?(toolMsg)

                            Task {
                                try? await chatProvider?.rejectFunction(id: id)
                            }
                        }
                    }
                }
            }
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { outerGeometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(
                                chat.messages.filter { message in
                                    if case .openai(let openAIMessage) = message,
                                        case .tool = openAIMessage.role
                                    {
                                        return false
                                    }
                                    return true
                                }
                            ) { message in
                                if let renderMessage = renderMessage {
                                    let (view, action) = renderMessage(
                                        message, chat.messages, chatProvider,
                                        getToolStatus(for: message, in: chat.messages)
                                    )
                                    switch action {
                                    case .replace:
                                        view
                                            .id(message.id)
                                    case .append:
                                        MessageRow(
                                            id: message.id,
                                            message: message,
                                            messages: chat.messages,
                                            status: status,
                                            isLastMessage: message.id == chat.messages.last?.id,
                                            onDelete: {
                                                if let index = chat.messages.firstIndex(where: {
                                                    $0.id == message.id
                                                }) {
                                                    onDelete?(index)
                                                }
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    chat.messages.removeAll(where: {
                                                        $0.id == message.id
                                                    })
                                                }
                                            },
                                            onEdit: { newContent in
                                                handleEdit(
                                                    messageId: message.id, newContent: newContent
                                                )
                                            },
                                            onRegenerate: {
                                                handleRegenerate(messageId: message.id)
                                            }
                                        )
                                        .id(message.id)
                                        view
                                    case .skip:
                                        MessageRow(
                                            id: message.id,
                                            message: message,
                                            messages: chat.messages,
                                            status: status,
                                            isLastMessage: message.id == chat.messages.last?.id,
                                            onDelete: {
                                                if let index = chat.messages.firstIndex(where: {
                                                    $0.id == message.id
                                                }) {
                                                    onDelete?(index)
                                                }
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    chat.messages.removeAll(where: {
                                                        $0.id == message.id
                                                    })
                                                }
                                            },
                                            onEdit: { newContent in
                                                handleEdit(
                                                    messageId: message.id, newContent: newContent
                                                )
                                            },
                                            onRegenerate: {
                                                handleRegenerate(messageId: message.id)
                                            }
                                        )
                                        .id(message.id)
                                    }
                                } else {
                                    MessageRow(
                                        id: message.id,
                                        message: message,
                                        messages: chat.messages,
                                        status: status,
                                        isLastMessage: message.id == chat.messages.last?.id,
                                        onDelete: {
                                            if let index = chat.messages.firstIndex(where: {
                                                $0.id == message.id
                                            }) {
                                                onDelete?(index)
                                            }
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                chat.messages.removeAll(where: {
                                                    $0.id == message.id
                                                })
                                            }
                                        },
                                        onEdit: { newContent in
                                            handleEdit(
                                                messageId: message.id, newContent: newContent
                                            )
                                        },
                                        onRegenerate: {
                                            handleRegenerate(messageId: message.id)
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)

                        VStack {}
                            .frame(height: 200)
                            .id("bottom")

                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("scroll")).maxY
                                )
                        }
                        .frame(height: 1)
                    }
                    .coordinateSpace(name: "scroll")
                    .onChange(of: initialChat) { _, newVal in
                        chat = newVal
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        // Check if near bottom - maxY is position of bottom marker in scroll coordinate space
                        // When at bottom, maxY should be close to scrollViewHeight
                        isAtBottom = maxY <= scrollViewHeight + 50
                    }
                    .onAppear {
                        scrollProxy = proxy
                        scrollViewHeight = outerGeometry.size.height
                        // Scroll to bottom when view first appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom()
                        }
                    }
                    .onChange(of: outerGeometry.size.height) { _, newHeight in
                        scrollViewHeight = newHeight
                    }
                }
            }

            VStack {
                // Scroll to bottom button
                if !isAtBottom {
                    if #available(macOS 26.0, *) {
                        Button(action: {
                            withAnimation {
                                scrollToBottom()
                            }
                        }) {
                            Label("Scroll to button", systemImage: "arrow.down")
                        }
                        .padding()
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.2), value: isAtBottom)

                    } else {
                        Button(action: {
                            withAnimation {
                                scrollToBottom()
                            }
                        }) {
                            Label("Scroll to button", systemImage: "arrow.down")
                        }
                        .padding()
                        .buttonStyle(.plain)
                        .buttonBorderShape(.capsule)
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.2), value: isAtBottom)
                    }
                }

                MessageInputView(
                    text: $newMessage,
                    status: isWaitingForToolResult ? .loading : status,
                    currentModel: $currentModel,
                    currentSource: $currentSource,
                    sources: sources,
                    onSend: { message in
                        newMessage = ""
                        sendMessage(message)
                    },
                    onCancel: {
                        handleCancel()
                    }
                )
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: InputHeightPreferenceKey.self, value: geometry.size.height
                            )
                    }
                )
            }
        }
        .onPreferenceChange(InputHeightPreferenceKey.self) { height in
            self.inputHeight = height
        }
        .alert(
            "Error to chat", isPresented: $showAlert,
            actions: {
                Button("OK", role: .cancel) {
                    showAlert = false
                }
            },
            message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
        )
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    @Previewable @State var chat = Chat(
        id: UUID(),
        gameId: "preview",
        messages: [
            .openai(.user(.init(content: "Hello, how are you?"))),
            .openai(
                .assistant(
                    .init(
                        content: "I'm doing well, thank you! How can I help you today?", audio: nil
                    )
                )),
        ]
    )

    @Previewable @State var currentModel = Model.openAI(
        OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")
    )

    @Previewable @State var currentSource = Source.openAI(
        client: OpenAIClient(apiKey: "sk-dummy"),
        models: [
            .openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")),
            .openAI(OpenAICompatibleModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo")),
        ]
    )

    AgentLayout(
        chat: chat,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [currentSource],
        onSend: { _ in
            // Message is already appended by AgentLayout
        }
    )
}
