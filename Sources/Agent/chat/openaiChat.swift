import Foundation
import JSONSchema

public enum OpenAIRole: String, Codable, Sendable {
    case user
    case assistant
    case tool
    case system
}

public enum OpenAIContentType: String, Codable, Sendable {
    case text
    case image
    case audio
}

public struct OpenAITextContentPart: Hashable, Codable, Sendable {
    public var text: String
    public var type: OpenAIContentType = .text

    public init(text: String) {
        self.text = text
    }
}

public struct OpenAIImageContentPart: Hashable, Codable, Sendable {
    public var type: OpenAIContentType = .image

    public struct ImageUrl: Hashable, Codable, Sendable {
        public enum Detail: String, Codable, Sendable {
            case auto
            case low
            case high
        }

        public let url: String
        public let detail: Detail?

        public init(url: String, detail: Detail?) {
            self.url = url
            self.detail = detail
        }
    }

    public let imageUrl: ImageUrl

    public init(imageUrl: ImageUrl) {
        self.imageUrl = imageUrl
    }
}

public struct OpenAIAudioContentPart: Hashable, Codable, Sendable {
    public var type: OpenAIContentType = .audio

    public struct InputAudio: Hashable, Codable, Sendable {
        public enum Format: String, Codable, Sendable {
            case wav
            case mp3
        }

        public var data: String
        public var format: Format

        public init(data: String, format: Format) {
            self.data = data
            self.format = format
        }
    }

    public let inputAudio: InputAudio

    public init(inputAudio: InputAudio) {
        self.inputAudio = inputAudio
    }
}

public enum OpenAIContentPart: Hashable, Codable, Sendable {
    case text(OpenAITextContentPart)
    case image(OpenAIImageContentPart)
    case audio(OpenAIAudioContentPart)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl
        case inputAudio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(OpenAIContentType.self, forKey: .type)
        switch type {
        case .text:
            let text = try container.decode(OpenAITextContentPart.self, forKey: .text)
            self = .text(text)
        case .image:
            let imageUrl = try container.decode(OpenAIImageContentPart.self, forKey: .imageUrl)
            self = .image(imageUrl)
        case .audio:
            let inputAudio = try container.decode(OpenAIAudioContentPart.self, forKey: .inputAudio)
            self = .audio(inputAudio)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(OpenAIContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let image):
            try container.encode(OpenAIContentType.image, forKey: .type)
            try container.encode(image, forKey: .imageUrl)
        case .audio(let audio):
            try container.encode(OpenAIContentType.audio, forKey: .type)
            try container.encode(audio, forKey: .inputAudio)
        }
    }
}

public enum OpenAIContent: Hashable, Codable, Sendable {
    case text(String)
    case contentParts([OpenAIContentPart])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            let parts = try container.decode([OpenAIContentPart].self)
            self = .contentParts(parts)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .contentParts(let parts):
            try container.encode(parts)
        }
    }
}

public struct OpenAIToolCall: Hashable, Codable, Sendable {
    public enum ToolType: String, Codable, Sendable {
        case function
    }

    public struct Function: Hashable, Codable, Sendable {
        public let name: String?
        public let arguments: String?
        public let thoughtSignature: String?

        enum CodingKeys: String, CodingKey {
            case name
            case arguments
            case thoughtSignature = "thought_signature"
        }

        public init(name: String?, arguments: String?, thoughtSignature: String? = nil) {
            self.name = name
            self.arguments = arguments
            self.thoughtSignature = thoughtSignature
        }
    }

    public let index: Int?
    public let id: String?
    public let type: ToolType?
    public let function: Function?

    public init(index: Int? = nil, id: String?, type: ToolType?, function: Function?) {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct OpenAITool: Codable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONSchema
    public var strict: Bool

    public init(name: String, description: String, parameters: JSONSchema, strict: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public struct OpenAIUserMessage: Hashable, Codable, Sendable {
    public let id: String
    public var role: OpenAIRole = .user
    public var content: String
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
    }

    public init(id: String = UUID().uuidString, content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try container.decodeIfPresent(OpenAIRole.self, forKey: .role) ?? .user
        self.content = try container.decode(String.self, forKey: .content)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct OpenAIAssistantMessage: Hashable, Codable, Sendable {
    public struct Audio: Hashable, Codable, Sendable {
        public let id: String
        public let data: String
        public let transcript: String

        public init(id: String, data: String, transcript: String) {
            self.id = id
            self.data = data
            self.transcript = transcript
        }
    }

    public struct ReasoningDetail: Hashable, Codable, Sendable {
        public let id: String?
        public let format: String?

        public init(id: String?, format: String?) {
            self.id = id
            self.format = format
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCalls = "tool_calls"
        case audio
        case reasoning
        case reasoningDetails = "reasoning_details"
    }

    public let id: String
    public var role: OpenAIRole = .assistant
    public let content: String?
    public let toolCalls: [OpenAIToolCall]?
    public let audio: Audio?
    public let reasoning: String?
    public let reasoningDetails: [ReasoningDetail]?

    public init(
        id: String? = nil, content: String? = nil, toolCalls: [OpenAIToolCall]? = nil, audio: Audio? = nil, reasoning: String? = nil, reasoningDetails: [ReasoningDetail]? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.content = content
        self.toolCalls = toolCalls
        self.audio = audio
        self.reasoning = reasoning
        self.reasoningDetails = reasoningDetails
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try container.decodeIfPresent(OpenAIRole.self, forKey: .role) ?? .assistant
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.toolCalls = try container.decodeIfPresent([OpenAIToolCall].self, forKey: .toolCalls)
        self.audio = try container.decodeIfPresent(Audio.self, forKey: .audio)
        self.reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        self.reasoningDetails = try container.decodeIfPresent([ReasoningDetail].self, forKey: .reasoningDetails)
    }

    /// Convert the response assistant message to request message. Will drop the audio.
    public func toRequestAssistantMessage() -> OpenAIAssistantMessage {
        return OpenAIAssistantMessage(
            id: id,
            content: content,
            toolCalls: toolCalls,
            audio: nil,
            reasoning: reasoning,
            reasoningDetails: reasoningDetails
        )
    }
}

public struct OpenAISystemMessage: Hashable, Codable, Sendable {
    public let id: String
    public var role: OpenAIRole = .system
    public let content: String

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
    }

    public init(id: String = UUID().uuidString, content: String) {
        self.id = id
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try container.decodeIfPresent(OpenAIRole.self, forKey: .role) ?? .system
        self.content = try container.decode(String.self, forKey: .content)
    }
}

public struct OpenAIToolMessage: Hashable, Codable, Sendable {
    public let id: String
    public var role: OpenAIRole = .tool
    public let content: String
    public let toolCallId: String
    public let name: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCallId = "tool_call_id"
        case name
    }

    public init(id: String = UUID().uuidString, content: String, toolCallId: String, name: String? = nil) {
        self.id = id
        self.content = content
        self.toolCallId = toolCallId
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try container.decodeIfPresent(OpenAIRole.self, forKey: .role) ?? .tool
        self.content = try container.decode(String.self, forKey: .content)
        self.toolCallId = try container.decode(String.self, forKey: .toolCallId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

public enum OpenAIMessage: Hashable, Codable, Sendable {
    case user(OpenAIUserMessage)
    case assistant(OpenAIAssistantMessage)
    case system(OpenAISystemMessage)
    case tool(OpenAIToolMessage)

    private enum CodingKeys: String, CodingKey {
        case role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(OpenAIRole.self, forKey: .role)
        switch role {
        case .user:
            let message = try OpenAIUserMessage(from: decoder)
            self = .user(message)
        case .assistant:
            let message = try OpenAIAssistantMessage(from: decoder)
            self = .assistant(message)
        case .system:
            let message = try OpenAISystemMessage(from: decoder)
            self = .system(message)
        case .tool:
            let message = try OpenAIToolMessage(from: decoder)
            self = .tool(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .user(let message):
            try message.encode(to: encoder)
        case .assistant(let message):
            try message.encode(to: encoder)
        case .system(let message):
            try message.encode(to: encoder)
        case .tool(let message):
            try message.encode(to: encoder)
        }
    }

    public var role: OpenAIRole {
        switch self {
        case .user(let message):
            return message.role
        case .assistant(let message):
            return message.role
        case .system(let message):
            return message.role
        case .tool(let message):
            return message.role
        }
    }

    public var content: String? {
        switch self {
        case .user(let message):
            return message.content
        case .assistant(let message):
            return message.content
        case .system(let message):
            return message.content
        case .tool(let message):
            return message.content
        }
    }
}
