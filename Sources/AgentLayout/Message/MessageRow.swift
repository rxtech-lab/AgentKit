//
//  MessageRow.swift
//  AgentLayout
//
//  Created by Qiwei Li on 5/19/25.
//

import Agent
import SwiftUI

typealias OnDelete = (() -> Void)?
typealias OnEdit = ((_ newContent: String) -> Void)?
typealias OnRegenerate = (() -> Void)?

struct MessageRow: View {
    let id: String
    let message: Message
    let messages: [Message]
    let status: ChatStatus
    let isLastMessage: Bool
    let onDelete: OnDelete
    let onEdit: OnEdit
    let onRegenerate: OnRegenerate

    init(
        id: String, message: Message, messages: [Message] = [],
        status: ChatStatus = .idle,
        isLastMessage: Bool = false,
        onDelete: OnDelete = nil,
        onEdit: OnEdit = nil, onRegenerate: OnRegenerate = nil
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
        switch message {
        case .openai(let openAIMessage, _):
            OpenAIMessageRow(
                id: id,
                message: openAIMessage,
                messages: messages.compactMap {
                    if case .openai(let message, _) = $0 {
                        return message
                    }
                    return nil
                },
                status: status,
                isLastMessage: isLastMessage,
                onDelete: onDelete,
                onEdit: onEdit,
                onRegenerate: onRegenerate
            )
        case .generic(let genericMessage, _):
            GenericMessageRow(
                id: id,
                message: genericMessage,
                messages: messages.map { $0.asGeneric },
                status: status,
                isLastMessage: isLastMessage,
                onDelete: onDelete,
                onEdit: onEdit,
                onRegenerate: onRegenerate
            )
        }
    }
}

#Preview {
    Group {
        MessageRow(id: "1", message: .openai(.user(.init(content: "Hi"))))
        MessageRow(id: "2", message: .user("Hello from generic!"))
        MessageRow(id: "3", message: .assistant("I'm a generic assistant response"))
    }
    .padding()
}
