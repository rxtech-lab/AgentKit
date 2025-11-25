import Foundation

public protocol ChatClient {
    func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol],
        maxTurns: Int
    ) -> AsyncThrowingStream<AgentResponsePart, Error>
}

extension ChatClient {
    public func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol]
    ) -> AsyncThrowingStream<AgentResponsePart, Error> {
        return process(messages: messages, model: model, tools: tools, maxTurns: 20)
    }
}
