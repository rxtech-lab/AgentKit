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

public struct AgentLayout: View {
    @State var chat: Chat
    private let initialChat: Chat
    @State private var newMessage: String = ""
    @State private var error: Error? = nil
    @State private var showAlert: Bool = false
    @State private var status: ChatStatus = .idle
    @State private var inputHeight: CGFloat = 80
    @State private var agentClient = AgentClient()

    @Binding var currentModel: Model
    @Binding var currentSource: Source
    let sources: [Source]

    let chatProvider: ChatProvider?
    let renderMessage: MessageRenderer?
    let onSend: ((String) -> Void)?
    let tools: [AgentTool]

    public init(
        chat: Chat,
        currentModel: Binding<Model>,
        currentSource: Binding<Source>,
        sources: [Source],
        chatProvider: ChatProvider? = nil,
        renderMessage: MessageRenderer? = nil,
        onSend: ((String) -> Void)? = nil,
        tools: [AgentTool] = []
    ) {
        self._chat = .init(initialValue: chat)
        self.initialChat = chat
        self._currentModel = currentModel
        self._currentSource = currentSource
        self.sources = sources
        self.chatProvider = chatProvider
        self.renderMessage = renderMessage
        self.onSend = onSend
        self.tools = tools
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(chat.messages) { message in
                            if let renderMessage = renderMessage {
                                let (view, action) = renderMessage(
                                    message, chat.messages, chatProvider
                                )
                                switch action {
                                case .replace:
                                    view
                                case .append:
                                    MessageRow(
                                        id: message.id,
                                        message: message,
                                        messages: chat.messages,
                                        onDelete: {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                chat.messages.removeAll(where: {
                                                    $0.id == message.id
                                                })
                                            }
                                        },
                                        onEdit: { _ in }
                                    )
                                    view
                                case .skip:
                                    EmptyView()
                                }
                            } else {
                                MessageRow(
                                    id: message.id,
                                    message: message,
                                    messages: chat.messages,
                                    onDelete: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            chat.messages.removeAll(where: { $0.id == message.id })
                                        }
                                    },
                                    onEdit: { _ in }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, inputHeight + 20)
                }
                .onChange(of: chat.messages) { _, _ in
                    if let lastMessage = chat.messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let lastMessage = chat.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: initialChat) { _, newVal in
                    chat = newVal
                }
            }

            MessageInputView(
                text: $newMessage,
                status: status,
                currentModel: $currentModel,
                currentSource: $currentSource,
                sources: sources,
                onSend: { message in
                    newMessage = ""

                    if let onSend = onSend {
                        onSend(message)
                    } else {
                        // Default logic using AgentClient
                        let userMsg = Message.openai(.user(.init(content: message)))
                        chat.messages.append(userMsg)

                        Task {
                            status = .loading
                            // Notify chatProvider if exists (persistence)
                            if let chatProvider = chatProvider {
                                try? await chatProvider.sendMessage(
                                    message: message, model: currentModel)
                            }

                            do {
                                let stream = await agentClient.process(
                                    messages: chat.messages,
                                    model: currentModel.id,
                                    tools: tools,
                                    source: currentSource
                                )

                                var currentAssistantId = UUID().uuidString
                                var currentAssistantContent = ""
                                var isFirstChunk = true

                                for try await part in stream {
                                    switch part {
                                    case .textDelta(let text):
                                        currentAssistantContent += text
                                        if isFirstChunk {
                                            let newMsg = Message.openai(
                                                .assistant(
                                                    .init(
                                                        id: currentAssistantId,
                                                        content: currentAssistantContent,
                                                        toolCalls: nil, audio: nil)))
                                            chat.messages.append(newMsg)
                                            isFirstChunk = false
                                        } else {
                                            let count = chat.messages.count
                                            if count > 0 {
                                                chat.messages[count - 1] = Message.openai(
                                                    .assistant(
                                                        .init(
                                                            id: currentAssistantId,
                                                            content: currentAssistantContent,
                                                            toolCalls: nil, audio: nil)))
                                            }
                                        }
                                    case .message(let msg):
                                        // Determine if we are updating the last message or appending a new one
                                        // msg is already of type Message (e.g. .openai(...))

                                        if case .openai(let openAIMsg) = msg,
                                            case .assistant = openAIMsg.role
                                        {
                                            if !isFirstChunk {
                                                let count = chat.messages.count
                                                if count > 0 {
                                                    chat.messages[count - 1] = msg
                                                }
                                            } else {
                                                chat.messages.append(msg)
                                            }
                                            // Prepare for next turn (potentially) or finish
                                            isFirstChunk = true
                                            currentAssistantContent = ""
                                            currentAssistantId = UUID().uuidString
                                        } else {
                                            chat.messages.append(msg)
                                        }
                                    case .error(let e):
                                        print("Agent Error: \(e)")
                                        self.error = e
                                        self.showAlert = true
                                    }
                                }
                                status = .idle
                            } catch {
                                print("Error sending message: \(error)")
                                self.error = error
                                self.showAlert = true
                                status = .idle
                            }
                        }
                    }
                },
                onCancel: {
                    // Handle cancel if needed
                }
            )
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: InputHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
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

    @Previewable @State var currentSource = Source(
        displayName: "OpenAI",
        endpoint: "https://api.openai.com/v1",
        apiKey: "sk-dummy",
        apiType: .openAI,
        models: [
            .openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")),
            .openAI(OpenAICompatibleModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo")),
        ]
    )

    return AgentLayout(
        chat: chat,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [currentSource],
        onSend: { message in
            let newMessage = Message.openai(.user(.init(content: message)))
            chat.messages.append(newMessage)

            // Simulate response
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let response = Message.openai(
                    .assistant(
                        .init(content: "This is a mock response to: \(message)", audio: nil)))
                chat.messages.append(response)
            }
        }
    )
}
