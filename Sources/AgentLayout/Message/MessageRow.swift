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
    let message: Message
    let onDelete: OnDelete
    let onEdit: OnEdit

    init(message: Message, onDelete: OnDelete = nil, onEdit: OnEdit = nil) {
        self.message = message
        self.onDelete = onDelete
        self.onEdit = onEdit
    }

    var body: some View {
        switch message {
        case .openai(let openAIMessage):
            OpenAIMessageRow(
                message: openAIMessage,
                onDelete: onDelete,
                onEdit: onEdit
            )
        }
    }
}


#Preview {
    MessageRow(message: .openai(.init(role: .assistant, content: "Hello")), onDelete: nil, onEdit: nil)
}
