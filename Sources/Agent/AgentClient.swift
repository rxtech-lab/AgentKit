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
    /// A custom agent source that only shows labels in the picker.
    /// No client is associated - the user handles message generation externally.
    case customAgent(id: String, displayName: String, models: [Model])

    public var id: String {
        switch self {
        case .openAI: return "openai"
        case .openRouter: return "openrouter"
        case .customAgent(let id, _, _): return id
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
        case .customAgent(_, let displayName, _): return displayName
        }
    }

    public var models: [Model] {
        switch self {
        case .openAI(_, let models): return models
        case .openRouter(_, let models): return models
        case .customAgent(_, _, let models): return models
        }
    }

    public var client: (any ChatClient)? {
        switch self {
        case .openAI(let client, _): return client
        case .openRouter(let client, _): return client
        case .customAgent: return nil
        }
    }
    
    /// Whether this source is a custom agent source
    public var isCustomAgent: Bool {
        if case .customAgent = self {
            return true
        }
        return false
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
            // Custom models can work with any source type that has a client
            guard let client = source.client else {
                throw AgentClientError.invalidSource
            }
            return client
        case .customAgent:
            // Custom agents don't use a client - this should not be called
            throw AgentClientError.invalidSource
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
