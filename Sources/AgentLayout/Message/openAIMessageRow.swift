//
//  ChatMessageRow.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//
import Agent
import SwiftUI

struct OpenAIMessageRow: View {
    let id: String
    var message: OpenAIMessage
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editedContent: String = ""
    var onDelete: OnDelete = nil
    var onEdit: OnEdit = nil

    // Computed properties to access message data
    private var content: String {
        return message.content
    }

    private var role: OpenAIRole {
        return message.role
    }

    var body: some View {
        let markdown = LocalizedStringKey(content)
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
                            .frame(maxWidth: 280, minHeight: 80, alignment: .trailing)
                    } else {
                        Text(markdown)
                            .padding(12)
                            .background(Color.gray.opacity(0.18))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: 280, alignment: .trailing)
                    }
                } else {
                    Text(markdown)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .foregroundColor(.primary)
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
                            editedContent = content
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
                        #if canImport(UIKit)
                            UIPasteboard.general.string = content
                        #elseif canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
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
            .opacity(isEditing || role == .assistant ? 1 : isHovering ? 1 : 0)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    Group {
        // OpenAIMessageRow(message: .init(role: .user, content: "Hello world"))
        // OpenAIMessageRow(message: .init(role: .assistant, content: "Hello world"))

        // OpenAIMessageRow(message: .init(role: .tool, content: "Hello world"))
    }
    .padding()
}
