//
//  Chat.swift
//
//  Created by Qiwei Li on 5/17/25.
//

import Foundation

public struct Chat {
    public var id: UUID
    public var gameId: String
    public var messages: [Message]

    public init(id: UUID, gameId: String, messages: [Message]) {
        self.id = id
        self.gameId = gameId
        self.messages = messages
    }
}

public enum Message: Identifiable, Hashable {
    case openai(OpenAIMessage)

    public var id: String {
        switch self {
        case .openai(let openAIMessage):
            return String(openAIMessage.hashValue)
        }
    }
}

public struct GameState {
    // Add your game state properties here
    public init() {}
}

public protocol ChatModelProtocol {
    func chat(history: [Message], text: String, gameState: GameState) async throws
        -> AsyncThrowingStream<OpenAIMessage, Error>
}

public struct ChatModel: ChatModelProtocol {
    public init() {}

    public func chat(history: [Message], text: String, gameState: GameState) async throws
        -> AsyncThrowingStream<OpenAIMessage, Error>
    {
        // Implement your chat logic here
        fatalError("Not implemented")
    }
}
