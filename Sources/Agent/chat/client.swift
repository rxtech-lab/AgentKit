import Foundation

public protocol ChatClient {
    func process(
        messages: [Message],
        model: Model,
        tools: [any AgentToolProtocol]
    ) -> AsyncThrowingStream<AgentResponsePart, Error>
}
