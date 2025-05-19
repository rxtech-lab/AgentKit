import Foundation

public enum OpenAIRole: String, Codable {
    case user
    case assistant
    case tool
    case system
}

public enum OpenAIContentType: String, Codable {
    case text
    case image
    case audio
}

public struct OpenAITextContentPart: Hashable, Codable {
    public var text: String
    public var type: OpenAIContentType = .text

    public init(text: String) {
        self.text = text
    }
}

public struct OpenAIImageContentPart: Hashable, Codable {
    public var type: OpenAIContentType = .image

    public struct ImageUrl: Hashable, Codable {
        public enum Detail: String, Codable {
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

public struct OpenAIAudioContentPart: Hashable, Codable {
    public var type: OpenAIContentType = .audio

    public struct InputAudio: Hashable, Codable {
        public enum Format: String, Codable {
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

public enum OpenAIContentPart: Hashable, Codable {
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

public enum OpenAIContent: Hashable, Codable {
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

public struct OpenAIToolCall: Hashable, Codable {
    public struct Function: Hashable, Codable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public let id: String
    public let type: String
    public let function: Function

    public init(id: String, type: String, function: Function) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct OpenAIUserMessage: Hashable, Codable {
    public var role: OpenAIRole = .user
    public var content: String
    public var createdAt: Date

    public init(content: String, createdAt: Date) {
        self.content = content
        self.createdAt = createdAt
    }
}

public struct OpenAIAssistantMessage: Hashable, Codable {
    public struct Audio: Hashable, Codable {
        public let id: String
        public let data: String
        public let transcript: String

        public init(id: String, data: String, transcript: String) {
            self.id = id
            self.data = data
            self.transcript = transcript
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCalls = "tool_calls"
        case audio
    }

    public let id: String?
    public var role: OpenAIRole = .assistant
    public let content: String
    public let toolCalls: [OpenAIToolCall]
    public let audio: Audio?

    public init(id: String? = nil, content: String, toolCalls: [OpenAIToolCall], audio: Audio?) {
        self.id = id
        self.content = content
        self.toolCalls = toolCalls
        self.audio = audio
    }

    /// Convert the response assistant message to request message. Will drop the audio.
    public func toRequestAssistantMessage() -> OpenAIAssistantMessage {
        return OpenAIAssistantMessage(
            id: id,
            content: content,
            toolCalls: toolCalls,
            audio: nil
        )
    }
}

public struct OpenAISystemMessage: Hashable, Codable {
    public var role: OpenAIRole = .system
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

public struct OpenAIToolMessage: Hashable, Codable {
    public var role: OpenAIRole = .tool
    public let content: String
    public let toolCallId: String

    public init(content: String, toolCallId: String) {
        self.content = content
        self.toolCallId = toolCallId
    }
}

public enum OpenAIMessage: Hashable, Codable {
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

    public var content: String {
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
