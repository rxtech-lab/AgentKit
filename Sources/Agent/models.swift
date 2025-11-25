import Foundation

/// Type of the api. Used to determine which client to use.
public enum ApiType: String, Sendable {
    /// Any openai compatible api should use this type
    case openAI = "openai"
    /// OpenRouter API
    case openRouter = "openrouter"
}

/// Represents the architecture of an AI model, including its input/output modalities and tokenizer.
public struct Architecture: Sendable, Hashable {
    public let inputModalities: [String]
    public let outputModalities: [String]
    public let tokenizer: String
}

/// Represents the pricing structure for using an AI model.
public struct Pricing: Sendable, Hashable {
    /// Cost per token for prompts
    public let prompt: Double
    /// Cost per token for completions
    public let completion: Double
    /// Cost per image
    public let image: Double
    /// Cost per request
    public let request: Double
    /// Cost for reading from input cache
    public let inputCacheRead: Double
    /// Cost for writing to input cache
    public let inputCacheWrite: Double
    /// Cost for web search operations
    public let webSearch: Double
    /// Cost for internal reasoning operations
    public let internalReasoning: Double
}

/// Configuration for extended thinking/reasoning tokens.
/// When enabled, the model will use extended thinking to reason through complex problems.
/// The reasoning content is preserved across tool calls to maintain context.
///
/// Note: Only models that include "reasoning" in their `supportedParameters` can use this feature.
public struct ReasoningConfig: Sendable, Hashable, Codable {
    /// Maximum number of tokens to use for reasoning
    public let maxTokens: Int

    /// Default reasoning configuration with 2000 tokens
    public static let `default` = ReasoningConfig(maxTokens: 2000)

    private enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
    }

    public init(maxTokens: Int) {
        self.maxTokens = maxTokens
    }
}

/// A model that implements the OpenAI model interface with additional OpenRouter-specific fields.
/// While maintaining compatibility with OpenAI's interface, this model includes extra properties
/// defined by OpenRouter to support additional functionality and metadata.
public struct OpenAICompatibleModel: Sendable, Identifiable, Hashable {
    // OpenAI compatible fields
    /// The ID of the model, used in completion requests
    public let id: String
    /// The display name of the model
    public let name: String?
    /// The creation date of the model as a Unix timestamp
    public let created: Int?
    /// A description of the model's capabilities and use cases
    public let description: String?
    /// The architectural details of the model
    public let architecture: Architecture?
    /// The pricing structure for using the model
    public let pricing: Pricing?
    /// The maximum context length supported by the model
    public let contextLength: Int?
    /// The Hugging Face model ID, if applicable
    public let huggingFaceId: String?
    /// Limits applied per request (e.g., token limits)
    public let perRequestLimits: [String: String]?
    /// Parameters that can be configured when using this model
    public let supportedParameters: [String]?
    /// Configuration for extended thinking/reasoning tokens.
    /// Set this to enable reasoning for models that support it (those with "reasoning" in supportedParameters).
    public let reasoningConfig: ReasoningConfig?

    /// Whether this model supports reasoning based on its supportedParameters
    public var supportsReasoning: Bool {
        supportedParameters?.contains("reasoning") ?? false
    }

    public init(
        id: String, name: String? = nil, created: Int? = nil, description: String? = nil,
        architecture: Architecture? = nil, pricing: Pricing? = nil, contextLength: Int? = nil,
        huggingFaceId: String? = nil, perRequestLimits: [String: String]? = nil,
        supportedParameters: [String]? = nil, reasoningConfig: ReasoningConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.description = description
        self.architecture = architecture
        self.pricing = pricing
        self.contextLength = contextLength
        self.huggingFaceId = huggingFaceId
        self.perRequestLimits = perRequestLimits
        self.supportedParameters = supportedParameters
        self.reasoningConfig = reasoningConfig
    }
}

public struct CustomModel: Identifiable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public enum Provider: Identifiable, Hashable, Sendable {
    case openAI
    case openRouter
    case custom(String)

    public var id: String {
        return rawValue
    }

    public var rawValue: String {
        switch self {
        case .custom(let id):
            return id
        case .openAI:
            return "openai"
        case .openRouter:
            return "openrouter"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    public static func == (lhs: Provider, rhs: Provider) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    public static var allCases: [String] {
        [
            "openai",
            "openrouter",
            "custom",
        ]
    }
}

public enum Model: Identifiable, Hashable, Sendable {
    /// An OpenAI compatible model
    case openAI(OpenAICompatibleModel)
    /// An OpenRouter model
    case openRouter(OpenAICompatibleModel)
    /// A custom model that you are using from an endpoint
    case custom(CustomModel)

    public var id: String {
        switch self {
        case .openAI(let model):
            return model.id
        case .openRouter(let model):
            return model.id
        case .custom(let model):
            return model.id
        }
    }

    public var displayName: String {
        switch self {
        case .openAI(let model):
            return model.name ?? model.id
        case .openRouter(let model):
            return model.name ?? model.id
        case .custom(let model):
            return model.id
        }
    }

    /// Get the reasoning configuration for this model.
    /// If the user specified a config, use it. Otherwise, auto-enable with default config
    /// if the model supports reasoning (has "reasoning" in supportedParameters).
    public var reasoningConfig: ReasoningConfig? {
        switch self {
        case .openAI(let model):
            // If user specified a config, use it
            if let config = model.reasoningConfig {
                return config
            }
            // Otherwise, auto-enable if model supports reasoning
            return model.supportsReasoning ? .default : nil
        case .openRouter(let model):
            // If user specified a config, use it
            if let config = model.reasoningConfig {
                return config
            }
            // Otherwise, auto-enable if model supports reasoning
            return model.supportsReasoning ? .default : nil
        case .custom:
            return nil
        }
    }
}
