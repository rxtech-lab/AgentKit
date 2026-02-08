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
    @State private var newMessage: String = ""
    @State private var error: Error? = nil
    @State private var showAlert: Bool = false
    @State private var inputHeight: CGFloat = 80
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isAtBottom: Bool = true
    @State private var scrollViewHeight: CGFloat = 0

    @Binding var currentModel: Model
    @Binding var currentSource: Source
    let sources: [Source]

    let chatProvider: ChatProvider
    let renderMessage: MessageRenderer?
    let contentMaxWidth: CGFloat

    // Setup configuration (stored for onAppear)
    private let chat: Chat
    private let systemPrompt: String?
    private let tools: [any AgentToolProtocol]
    private let onSend: ((Message) -> Void)?
    private let onMessage: ((Message) -> Void)?
    private let onDelete: ((Int) -> Void)?
    private let onEdit: ((Int, Message) -> Void)?
    private let onMessageChange: (([Message]) -> Void)?
    private let onCustomAgentSend: ((String, [Message]) -> Void)?

    public init(
        chatProvider: ChatProvider,
        chat: Chat,
        currentModel: Binding<Model>,
        currentSource: Binding<Source>,
        sources: [Source],
        systemPrompt: String? = nil,
        tools: [any AgentToolProtocol] = [],
        onSend: ((Message) -> Void)? = nil,
        onMessage: ((Message) -> Void)? = nil,
        onDelete: ((Int) -> Void)? = nil,
        onEdit: ((Int, Message) -> Void)? = nil,
        onMessageChange: (([Message]) -> Void)? = nil,
        onCustomAgentSend: ((String, [Message]) -> Void)? = nil,
        renderMessage: MessageRenderer? = nil,
        contentMaxWidth: CGFloat = 800
    ) {
        self.chatProvider = chatProvider
        self.chat = chat
        self._currentModel = currentModel
        self._currentSource = currentSource
        self.sources = sources
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.onSend = onSend
        self.onMessage = onMessage
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onMessageChange = onMessageChange
        self.onCustomAgentSend = onCustomAgentSend
        self.renderMessage = renderMessage
        self.contentMaxWidth = contentMaxWidth
    }

    // MARK: - Private Methods

    private func scrollToBottom() {
        guard let lastMessage = chatProvider.messages.last else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .top)
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { outerGeometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(
                                chatProvider.messages.filter { message in
                                    // Filter out tool messages (they are displayed inline with assistant messages)
                                    return message.role != .tool
                                }
                            ) { message in
                                if let renderMessage = renderMessage {
                                    let (view, action) = renderMessage(
                                        message, chatProvider.messages, chatProvider,
                                        chatProvider.getToolStatus(for: message, in: chatProvider.messages)
                                    )
                                    switch action {
                                    case .replace:
                                        view
                                            .id(message.id)
                                    case .append:
                                        MessageRow(
                                            id: message.id,
                                            message: message,
                                            messages: chatProvider.messages,
                                            status: chatProvider.status,
                                            isLastMessage: message.id == chatProvider.messages.last?.id,
                                            onDelete: {
                                                if let index = chatProvider.messages.firstIndex(where: {
                                                    $0.id == message.id
                                                }) {
                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        chatProvider.deleteMessage(at: index)
                                                    }
                                                }
                                            },
                                            onEdit: { newContent in
                                                chatProvider.edit(
                                                    messageId: message.id, newContent: newContent
                                                )
                                            },
                                            onRegenerate: {
                                                chatProvider.regenerate(messageId: message.id)
                                            }
                                        )
                                        .id(message.id)
                                        view
                                    case .skip:
                                        MessageRow(
                                            id: message.id,
                                            message: message,
                                            messages: chatProvider.messages,
                                            status: chatProvider.status,
                                            isLastMessage: message.id == chatProvider.messages.last?.id,
                                            onDelete: {
                                                if let index = chatProvider.messages.firstIndex(where: {
                                                    $0.id == message.id
                                                }) {
                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        chatProvider.deleteMessage(at: index)
                                                    }
                                                }
                                            },
                                            onEdit: { newContent in
                                                chatProvider.edit(
                                                    messageId: message.id, newContent: newContent
                                                )
                                            },
                                            onRegenerate: {
                                                chatProvider.regenerate(messageId: message.id)
                                            }
                                        )
                                        .id(message.id)
                                    }
                                } else {
                                    MessageRow(
                                        id: message.id,
                                        message: message,
                                        messages: chatProvider.messages,
                                        status: chatProvider.status,
                                        isLastMessage: message.id == chatProvider.messages.last?.id,
                                        onDelete: {
                                            if let index = chatProvider.messages.firstIndex(where: {
                                                $0.id == message.id
                                            }) {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    chatProvider.deleteMessage(at: index)
                                                }
                                            }
                                        },
                                        onEdit: { newContent in
                                            chatProvider.edit(
                                                messageId: message.id, newContent: newContent
                                            )
                                        },
                                        onRegenerate: {
                                            chatProvider.regenerate(messageId: message.id)
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .frame(maxWidth: contentMaxWidth)
                        .frame(maxWidth: .infinity)

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
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        // Check if near bottom - maxY is position of bottom marker in scroll coordinate space
                        // When at bottom, maxY should be close to scrollViewHeight
                        isAtBottom = maxY <= scrollViewHeight + 50
                    }
                    .onAppear {
                        scrollProxy = proxy
                        scrollViewHeight = outerGeometry.size.height

                        // Setup ChatProvider with configuration
                        chatProvider.setup(
                            chat: chat,
                            currentModel: currentModel,
                            currentSource: currentSource,
                            systemPrompt: systemPrompt,
                            tools: tools,
                            onSend: onSend,
                            onMessage: onMessage,
                            onDelete: onDelete,
                            onEdit: onEdit,
                            onMessageChange: onMessageChange,
                            onCustomAgentSend: onCustomAgentSend
                        )

                        chatProvider.scrollToBottom = {
                            guard let lastMessage = chatProvider.messages.last else { return }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .top)
                            }
                        }
                        chatProvider.onError = { err in
                            error = err
                            showAlert = true
                        }
                        // Scroll to bottom when view first appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom()
                        }
                    }
                    .onChange(of: currentModel) { _, newValue in
                        chatProvider.currentModel = newValue
                    }
                    .onChange(of: currentSource) { _, newValue in
                        chatProvider.currentSource = newValue
                    }
                    .onChange(of: chat) { _, newValue in
                        chatProvider.updateChat(newValue)
                    }
                    .onChange(of: systemPrompt) { _, newValue in
                        chatProvider.updateSystemPrompt(newValue)
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
                    status: chatProvider.isWaitingForToolResult ? .loading : chatProvider.status,
                    currentModel: $currentModel,
                    currentSource: $currentSource,
                    sources: sources,
                    onSend: { message in
                        newMessage = ""
                        chatProvider.send(message)
                    },
                    onCancel: {
                        chatProvider.cancel()
                    }
                )
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
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

    let chat = Chat(
        id: UUID(),
        gameId: "preview",
        messages: [
            // OpenAI message format
            .openai(.user(.init(content: "Hello, how are you?"))),
            .openai(
                .assistant(
                    .init(
                        content: "I'm doing well, thank you! How can I help you today?", audio: nil
                    )
                )),
            // Generic message format (convenience initializers)
            .user("This is a generic user message"),
            .assistant("This is a generic assistant response"),
        ]
    )

    let chatProvider = ChatProvider()

    AgentLayout(
        chatProvider: chatProvider,
        chat: chat,
        currentModel: $currentModel,
        currentSource: $currentSource,
        sources: [currentSource]
    )
}
