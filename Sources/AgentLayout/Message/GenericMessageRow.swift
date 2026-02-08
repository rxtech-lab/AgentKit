//
//  GenericMessageRow.swift
//  AgentLayout
//
//  Generic message row for rendering messages from any provider.
//

import Agent
import MarkdownUI
import Splash
import SwiftUI

struct GenericMessageRow: View {
    let id: String
    let message: GenericMessage
    let messages: [GenericMessage]
    let status: ChatStatus
    let isLastMessage: Bool
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editedContent: String = ""
    @State private var hideTask: Task<Void, Never>?
    var onDelete: OnDelete = nil
    var onEdit: OnEdit = nil
    var onRegenerate: OnRegenerate = nil

    // Computed properties
    private var content: String? {
        return message.content
    }

    private var role: MessageRole {
        return message.role
    }

    private var hasToolCalls: Bool {
        if case .assistant(let assistantMessage) = message {
            return assistantMessage.toolCalls != nil && !assistantMessage.toolCalls!.isEmpty
        }
        return false
    }

    private var toolCalls: [ToolCall] {
        if case .assistant(let assistantMessage) = message {
            return assistantMessage.toolCalls ?? []
        }
        return []
    }

    private var reasoning: ReasoningContent? {
        if case .assistant(let assistantMessage) = message {
            return assistantMessage.reasoning
        }
        return nil
    }

    private var hasReasoningContent: Bool {
        if let reasoning = reasoning {
            if reasoning.text != nil || reasoning.summary != nil {
                return true
            }
        }
        if isLastMessage && status == .loading {
            return true
        }
        return false
    }

    public init(
        id: String, message: GenericMessage, messages: [GenericMessage] = [],
        status: ChatStatus = .idle,
        isLastMessage: Bool = false,
        onDelete: OnDelete = nil, onEdit: OnEdit = nil, onRegenerate: OnRegenerate = nil
    ) {
        self.id = id
        self.message = message
        self.status = status
        self.isLastMessage = isLastMessage
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onRegenerate = onRegenerate
        self.messages = messages
    }

    var body: some View {
        VStack(alignment: role == .user ? .trailing : .leading) {
            HStack(alignment: .top) {
                if role == .user {
                    Spacer()
                    if isEditing {
                        TextEditor(text: $editedContent)
                            .padding(8)
                            .background(Color.gray.opacity(0.18))
                            .cornerRadius(16)
                            .textEditorStyle(.plain)
                            .frame(maxWidth: 400, minHeight: 80, alignment: .trailing)
                    } else {
                        if let content = content {
                            Markdown(content)
                                .markdownTheme(.chatTheme)
                                .markdownCodeSyntaxHighlighter(
                                    SplashCodeSyntaxHighlighter(
                                        theme: .wwdc18(withFont: .init(size: 14)))
                                )
                                .textSelection(.enabled)
                                .padding(12)
                                .background(Color.gray.opacity(0.18))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .frame(maxWidth: 400, alignment: .trailing)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        // Thinking/reasoning content (expandable)
                        if hasReasoningContent {
                            ThinkingContentView(
                                summary: reasoning?.summary,
                                reasoning: reasoning?.text,
                                status: status
                            )
                            .padding(.horizontal, 12)
                        }

                        if let content = content {
                            Markdown(content)
                                .markdownTheme(.chatTheme)
                                .markdownCodeSyntaxHighlighter(
                                    SplashCodeSyntaxHighlighter(
                                        theme: .wwdc18(withFont: .init(size: 14)))
                                )
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .foregroundColor(.primary)
                                .frame(maxWidth: 600, alignment: .leading)
                        }
                    }
                    Spacer()
                }
            }

            // Tool calls for assistant messages
            if role == .assistant && hasToolCalls {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(toolCalls, id: \.id) { toolCall in
                        GenericToolMessageRow(
                            toolCall: toolCall,
                            messages: messages,
                            status: status
                        )
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 4)
            }

            // Blinking dot for loading state when no content yet
            if role == .assistant && isLastMessage && status == .loading
                && (content == nil || content?.isEmpty == true)
            {
                HStack {
                    BlinkingDot()
                        .padding(.leading, 12)
                        .padding(.top, 10)
                    Spacer()
                }
            }

            // action buttons
            HStack {
                if role == .user {
                    Spacer()

                    if isEditing {
                        Button(action: {
                            isEditing = false
                        }) {
                            Text("Cancel")
                                .foregroundStyle(Color.gray)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)

                        Button(action: {
                            onEdit?(editedContent)
                            isEditing = false
                        }) {
                            Text("Submit")
                                .foregroundStyle(Color.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            editedContent = content ?? ""
                            isEditing = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.gray.opacity(1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !isEditing {
                    Button(action: {
                        onRegenerate?()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.gray.opacity(1))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        #if canImport(UIKit)
                            UIPasteboard.general.string = content
                        #elseif canImport(AppKit)
                            if let content = content {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(content, forType: .string)
                            }
                        #endif
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Color.gray.opacity(1))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation {
                            onDelete?()
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.gray.opacity(1))
                    }
                    .buttonStyle(.plain)
                }

                if role != .user {
                    Spacer()
                }
            }
            .opacity(isEditing || isHovering ? 1 : 0)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .onHover { hovering in
            if hovering {
                hideTask?.cancel()
                hideTask = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = true
                }
            } else {
                hideTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHovering = false
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Generic Tool Message Row

struct GenericToolMessageRow: View {
    let toolCall: ToolCall
    let messages: [GenericMessage]
    let status: ChatStatus
    
    @State private var isExpanded: Bool = false
    
    private var toolResponse: ToolMessage? {
        for msg in messages {
            if case .tool(let toolMsg) = msg, toolMsg.toolCallId == toolCall.id {
                return toolMsg
            }
        }
        return nil
    }
    
    private var hasResponse: Bool {
        return toolResponse != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    
                    Text(toolCall.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if !hasResponse && status == .loading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if hasResponse {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        FormattedJSONText(jsonString: toolCall.arguments)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                    }
                    
                    if let response = toolResponse {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Response")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            FormattedJSONText(jsonString: response.content)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 10)
            }
        }
    }
}

#Preview("Generic Messages") {
    ScrollView {
        VStack(spacing: 16) {
            // User message
            GenericMessageRow(
                id: "1",
                message: .user(UserMessage(content: "Hello world"))
            )
            
            // Simple assistant message
            GenericMessageRow(
                id: "2",
                message: .assistant(AssistantMessage(content: "How can I help you today?"))
            )
            
            // Assistant with tool calls
            GenericMessageRow(
                id: "3",
                message: .assistant(AssistantMessage(
                    content: "I'll check the weather for you.",
                    toolCalls: [
                        ToolCall(id: "tool1", name: "GetWeather", arguments: "{\"location\": \"New York\"}")
                    ]
                )),
                messages: [
                    .tool(ToolMessage(toolCallId: "tool1", name: "GetWeather", content: "{\"temperature\": 72, \"condition\": \"sunny\"}"))
                ]
            )
        }
    }
    .padding()
}

#Preview("With Reasoning") {
    ScrollView {
        VStack(spacing: 16) {
            GenericMessageRow(
                id: "1",
                message: .assistant(AssistantMessage(
                    content: "The answer is 42.",
                    reasoning: ReasoningContent(
                        text: "Let me think about this step by step...\n\n1. First, I consider the question\n2. Then I analyze the context\n3. Finally, I arrive at the conclusion",
                        summary: "Analyzed the question systematically"
                    )
                ))
            )
        }
    }
    .padding()
}

#Preview("Loading State") {
    ScrollView {
        VStack(spacing: 16) {
            // Loading with no content yet
            GenericMessageRow(
                id: "1",
                message: .assistant(AssistantMessage(content: nil)),
                status: .loading,
                isLastMessage: true
            )
            
            // Loading with partial content
            GenericMessageRow(
                id: "2",
                message: .assistant(AssistantMessage(content: "I'm thinking about your question...")),
                status: .loading,
                isLastMessage: true
            )
            
            // Loading tool call (no response yet)
            GenericMessageRow(
                id: "3",
                message: .assistant(AssistantMessage(
                    content: "Let me search for that.",
                    toolCalls: [
                        ToolCall(id: "tool1", name: "SearchWeb", arguments: "{\"query\": \"Swift concurrency\"}")
                    ]
                )),
                messages: [],
                status: .loading,
                isLastMessage: true
            )
        }
    }
    .padding()
}

#Preview("Long Content") {
    ScrollView {
        VStack(spacing: 16) {
            GenericMessageRow(
                id: "1",
                message: .user(UserMessage(content: "Can you explain Swift's async/await pattern in detail?"))
            )
            
            GenericMessageRow(
                id: "2",
                message: .assistant(AssistantMessage(content: """
                    # Swift Async/Await
                    
                    Swift's async/await is a powerful concurrency model introduced in Swift 5.5.
                    
                    ## Key Concepts
                    
                    1. **async functions** - Functions that can suspend execution
                    2. **await keyword** - Marks potential suspension points
                    3. **Task** - A unit of asynchronous work
                    
                    ## Example
                    
                    ```swift
                    func fetchData() async throws -> Data {
                        let url = URL(string: "https://api.example.com")!
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return data
                    }
                    ```
                    
                    This pattern makes asynchronous code much more readable than callback-based approaches.
                    """))
            )
        }
    }
    .padding()
}

#Preview("Multiple Tool Calls") {
    ScrollView {
        VStack(spacing: 16) {
            GenericMessageRow(
                id: "1",
                message: .assistant(AssistantMessage(
                    content: "I'll gather the information you need.",
                    toolCalls: [
                        ToolCall(id: "tool1", name: "GetUserProfile", arguments: "{\"userId\": \"123\"}"),
                        ToolCall(id: "tool2", name: "GetUserOrders", arguments: "{\"userId\": \"123\", \"limit\": 5}"),
                        ToolCall(id: "tool3", name: "GetRecommendations", arguments: "{\"userId\": \"123\", \"category\": \"electronics\"}")
                    ]
                )),
                messages: [
                    .tool(ToolMessage(toolCallId: "tool1", name: "GetUserProfile", content: "{\"name\": \"John Doe\", \"email\": \"john@example.com\"}")),
                    .tool(ToolMessage(toolCallId: "tool2", name: "GetUserOrders", content: "[{\"id\": 1, \"item\": \"Laptop\"}, {\"id\": 2, \"item\": \"Mouse\"}]")),
                    .tool(ToolMessage(toolCallId: "tool3", name: "GetRecommendations", content: "[\"Keyboard\", \"Monitor\", \"USB Hub\"]"))
                ]
            )
        }
    }
    .padding()
}
