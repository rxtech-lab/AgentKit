//
//  Chat.swift
//
//  Created by Qiwei Li on 5/17/25.
//

import Foundation

public struct Chat: Identifiable, Equatable, Hashable {
    public var id: UUID
    public var gameId: String
    public var messages: [Message]

    public init(id: UUID, gameId: String, messages: [Message]) {
        self.id = id
        self.gameId = gameId
        self.messages = messages
    }
}

public enum ChatStatus {
    case idle
    case loading
}

public enum Message: Identifiable, Hashable, Sendable, Codable {
    case openai(OpenAIMessage)

    public var id: String {
        switch self {
        case .openai(let openAIMessage):
            switch openAIMessage {
            case .user(let msg):
                return msg.id
            case .assistant(let msg):
                return msg.id
            case .system(let msg):
                return msg.id
            case .tool(let msg):
                return msg.id
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    private enum MessageType: String, Codable {
        case openai
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .openai:
            let message = try container.decode(OpenAIMessage.self, forKey: .message)
            self = .openai(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .openai(let message):
            try container.encode(MessageType.openai, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
