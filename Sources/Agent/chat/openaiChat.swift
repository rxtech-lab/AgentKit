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

public struct OpenAITextContentPart: Hashable {
    public var text: String
    public let type: OpenAIContentType = .text

    public init(text: String) {
        self.text = text
    }
}

public struct OpenAIImageContentPart: Hashable {
    public let type: OpenAIContentType = .image

    public struct ImageUrl: Hashable {
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

public struct OpenAIAudioContentPart: Hashable {
    public let type: OpenAIContentType = .audio

    public struct InputAudio: Hashable {
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

public enum OpenAIContentPart: Hashable {
    case text(OpenAITextContentPart)
    case image(OpenAIImageContentPart)
    case audio(OpenAIAudioContentPart)
}

public enum OpenAIContent: Hashable {
    case text(String)
    case contentParts([OpenAIContentPart])
}

public struct OpenAIToolCall: Hashable {
    public struct Function: Hashable {
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

public struct OpenAIUserMessage: Hashable {
    public let role: OpenAIRole = .user
    public var content: String
    public var createdAt: Date

    public init(content: String, createdAt: Date) {
        self.content = content
        self.createdAt = createdAt
    }
}

public struct OpenAIAssistantMessage: Hashable {
    public struct Audio: Hashable {
        public let id: String
        public let data: String
        public let transcript: String

        public init(id: String, data: String, transcript: String) {
            self.id = id
            self.data = data
            self.transcript = transcript
        }
    }

    public let role: OpenAIRole = .assistant
    public let content: String
    public let toolCalls: [OpenAIToolCall]
    public let audio: Audio?

    public init(content: String, toolCalls: [OpenAIToolCall], audio: Audio?) {
        self.content = content
        self.toolCalls = toolCalls
        self.audio = audio
    }

    /// Convert the response assistant message to request message. Will drop the audio.
    public func toRequestAssistantMessage() -> OpenAIAssistantMessage {
        return OpenAIAssistantMessage(
            content: content,
            toolCalls: toolCalls,
            audio: nil
        )
    }
}

public struct OpenAISystemMessage: Hashable {
    public let role: OpenAIRole = .system
    public let content: String

    public init(content: String) {
        self.content = content
    }
}

public struct OpenAIToolMessage: Hashable {
    public let role: OpenAIRole = .tool
    public let content: String
    public let toolCallId: String

    public init(content: String, toolCallId: String) {
        self.content = content
        self.toolCallId = toolCallId
    }
}

public enum OpenAIMessage: Hashable {
    case user(OpenAIUserMessage)
    case assistant(OpenAIAssistantMessage)
    case system(OpenAISystemMessage)
    case tool(OpenAIToolMessage)
}
