//
//  ChatMessageRow.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//
import Agent
import MarkdownUI
import Shimmer
import Splash
import SwiftUI

struct BlinkingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.primary)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

struct OpenAIMessageRow: View {
    let id: String
    let message: OpenAIMessage
    let messages: [OpenAIMessage]
    let status: ChatStatus
    let isLastMessage: Bool
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editedContent: String = ""
    @State private var hideTask: Task<Void, Never>?
    var onDelete: OnDelete = nil
    var onEdit: OnEdit = nil
    var onRegenerate: OnRegenerate = nil

    // Computed properties to access message data
    private var content: String? {
        return message.content
    }

    private var role: OpenAIRole {
        return message.role
    }

    private var hasToolCalls: Bool {
        if case .assistant(let assistantMessage) = message {
            return assistantMessage.toolCalls != nil && !assistantMessage.toolCalls!.isEmpty
        }
        return false
    }

    private var toolCalls: [OpenAIToolCall] {
        if case .assistant(let assistantMessage) = message {
            return assistantMessage.toolCalls ?? []
        }
        return []
    }

    public init(
        id: String, message: OpenAIMessage, messages: [OpenAIMessage] = [],
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
                    Spacer()
                }
            }

            // Tool calls for assistant messages
            if role == .assistant && hasToolCalls {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(toolCalls, id: \.id) { toolCall in
                        OpenAIToolMessageRow(
                            toolCall: toolCall,
                            messages: messages,
                            status: status)
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
                    // Regenerate button for assistant messages
                    if role == .assistant {
                        Button(action: {
                            onRegenerate?()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.gray.opacity(1))
                        }
                        .buttonStyle(.plain)
                    }

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
                // Cancel any pending hide task and show immediately
                hideTask?.cancel()
                hideTask = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = true
                }
            } else {
                // Delay hiding the actions
                hideTask = Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 2 seconds
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

#Preview {
    ScrollView {
        OpenAIMessageRow(id: "1", message: .user(.init(content: "Hello world")))
        OpenAIMessageRow(
            id: "1",
            message: .assistant(.init(content: "How can I help you?", toolCalls: [], audio: nil)))
        OpenAIMessageRow(
            id: "1",
            message: .assistant(
                .init(
                    content: "I'll check the weather for you.",
                    toolCalls: [
                        .init(
                            id: "tool1", type: .function,
                            function: .init(
                                name: "GetWeather", arguments: "{\"location\": \"New York\"}"))
                    ], audio: nil)),
            messages: [
                .tool(
                    .init(
                        content: "{\"temperature\": 72, \"condition\": \"sunny\"}",
                        toolCallId: "tool1"))
            ])
        OpenAIMessageRow(
            id: "1",
            message: .assistant(
                .init(
                    content:
                        "I'm checking the weather for you.\n```swift\nlet weather = getWeather(location: \"Los Angeles\")\nprint(weather)\n```",
                    toolCalls: [
                        .init(
                            id: "tool2", type: .function,
                            function: .init(
                                name: "GetWeather", arguments: "{\"location\": \"Los Angeles\"}"))
                    ], audio: nil)),
            status: .loading)
    }
    .padding()
}
