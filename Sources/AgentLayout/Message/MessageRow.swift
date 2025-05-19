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

struct MessageRow: View {
    let id: String
    let message: Message
    let messages: [Message]
    let onDelete: OnDelete
    let onEdit: OnEdit

    init(id: String, message: Message, messages: [Message] = [], onDelete: OnDelete = nil, onEdit: OnEdit = nil) {
        self.id = id
        self.message = message
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.messages = messages
    }

    var body: some View {
        switch message {
        case .openai(let openAIMessage):
            OpenAIMessageRow(
                id: id,
                message: openAIMessage,
                messages: messages.compactMap {
                    if case .openai(let message) = $0 {
                        return message
                    }
                    return nil

                },
                onDelete: onDelete,
                onEdit: onEdit
            )
        }
    }
}


 #Preview {
    Group {
        MessageRow(id: "1", message: .openai(.user(.init(content: "Hi"))))
    }
    .padding()
 }
