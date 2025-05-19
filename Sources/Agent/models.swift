/// Type of the api. Used to determine which client to use.
public enum ApiType: String {
    /// Any openai compatible api should use this type
    case openAI = "openai"
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

    public init(
        id: String, name: String? = nil, created: Int? = nil, description: String? = nil,
        architecture: Architecture? = nil, pricing: Pricing? = nil, contextLength: Int? = nil,
        huggingFaceId: String? = nil, perRequestLimits: [String: String]? = nil,
        supportedParameters: [String]? = nil
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
    }
}

public struct CustomModel: Identifiable, Hashable {
    public let id: String
    public let endpoint: String
    public let apiKey: String
    public let apiType: ApiType

    public init(id: String, endpoint: String, apiKey: String, apiType: ApiType) {
        self.id = id
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.apiType = apiType
    }
}

public enum Provider: Identifiable, Hashable {
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

public enum Model: Identifiable, Hashable {
    /// An OpenAI, OpenRouter, or other compatible model
    /// If you are using custom endpoints, you can use the `custom` case
    case openAI(OpenAICompatibleModel)
    /// A custom model that you are using from an endpoint
    case custom(CustomModel)

    public var id: String {
        switch self {
        case .openAI(let model):
            return model.id
        case .custom(let model):
            return model.id
        }
    }

    public var displayName: String {
        switch self {
        case .openAI(let model):
            return model.name ?? model.id
        case .custom(let model):
            return model.id
        }
    }
}
