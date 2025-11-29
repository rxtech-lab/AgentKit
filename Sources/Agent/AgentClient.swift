import Combine
import Foundation

public enum AgentResponsePart: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case message(Message)
    case error(Error)
}

public enum AgentClientError: LocalizedError {
    case invalidURL
    case missingCredentials
    case invalidSource

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL in endpoint."
        case .missingCredentials:
            return "Missing API key or endpoint."
        case .invalidSource:
            return "Invalid source."
        }
    }
}

public enum Source: Identifiable, Sendable, Equatable {
    case openAI(client: OpenAIClient, models: [Model])
    case openRouter(client: OpenRouterClient, models: [Model])

    public var id: String {
        switch self {
        case .openAI: return "openai"
        case .openRouter: return "openrouter"
        }
    }

    public static func == (lhs: Source, rhs: Source) -> Bool {
        // Compare by id and models for SwiftUI change detection
        lhs.id == rhs.id && lhs.models == rhs.models
    }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        }
    }

    public var models: [Model] {
        switch self {
        case .openAI(_, let models): return models
        case .openRouter(_, let models): return models
        }
    }

    public var client: any ChatClient {
        switch self {
        case .openAI(let client, _): return client
        case .openRouter(let client, _): return client
        }
    }
}

public actor AgentClient {
    public init() {}

    private func createClient(for model: Model, source: Source) throws -> any ChatClient {
        switch model {
        case .openAI:
            if case .openAI(let client, _) = source {
                return client
            }
            throw AgentClientError.invalidSource
        case .openRouter:
            if case .openRouter(let client, _) = source {
                return client
            }
            throw AgentClientError.invalidSource
        case .custom:
            // Custom models can work with any source type
            return source.client
        }
    }

    public func process(
        messages: [Message],
        model: Model,
        source: Source,
        tools: [any AgentToolProtocol]
    ) -> AsyncThrowingStream<AgentResponsePart, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let client = try self.createClient(for: model, source: source)
                    let stream = client.process(
                        messages: messages,
                        model: model,
                        tools: tools
                    )

                    for try await part in stream {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
