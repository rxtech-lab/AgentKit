import Foundation
import JSONSchema

public enum GeminiRole: String, Codable, Sendable {
    case user
    case model
}

public enum GeminiContentType: String, Codable, Sendable {
    case text
    case inlineData = "inline_data"
    case functionCall = "function_call"
    case functionResponse = "function_response"
}

public struct GeminiTextPart: Hashable, Codable, Sendable {
    public var text: String
    
    public init(text: String) {
        self.text = text
    }
}

public struct GeminiInlineData: Hashable, Codable, Sendable {
    public let mimeType: String
    public let data: String
    
    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

public struct GeminiFunctionCall: Hashable, Codable, Sendable {
    public let name: String
    public let args: [String: String]
    
    public init(name: String, args: [String: String]) {
        self.name = name
        self.args = args
    }
}

public struct GeminiFunctionResponse: Hashable, Codable, Sendable {
    public let name: String
    public let response: [String: String]
    
    public init(name: String, response: [String: String]) {
        self.name = name
        self.response = response
    }
}

public enum GeminiPart: Hashable, Codable, Sendable {
    case text(GeminiTextPart)
    case inlineData(GeminiInlineData)
    case functionCall(GeminiFunctionCall)
    case functionResponse(GeminiFunctionResponse)
    
    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
        case functionCall
        case functionResponse
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let text = try? container.decode(String.self, forKey: .text) {
            self = .text(GeminiTextPart(text: text))
        } else if let inlineData = try? container.decode(GeminiInlineData.self, forKey: .inlineData) {
            self = .inlineData(inlineData)
        } else if let functionCall = try? container.decode(GeminiFunctionCall.self, forKey: .functionCall) {
            self = .functionCall(functionCall)
        } else if let functionResponse = try? container.decode(GeminiFunctionResponse.self, forKey: .functionResponse) {
            self = .functionResponse(functionResponse)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: CodingKeys.text,
                in: container,
                debugDescription: "Unable to decode GeminiPart"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let textPart):
            try container.encode(textPart.text, forKey: .text)
        case .inlineData(let inlineData):
            try container.encode(inlineData, forKey: .inlineData)
        case .functionCall(let functionCall):
            try container.encode(functionCall, forKey: .functionCall)
        case .functionResponse(let functionResponse):
            try container.encode(functionResponse, forKey: .functionResponse)
        }
    }
}

public struct GeminiContent: Hashable, Codable, Sendable {
    public let role: GeminiRole?
    public let parts: [GeminiPart]
    
    public init(role: GeminiRole?, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

public struct GeminiUserMessage: Hashable, Codable, Sendable {
    public var role: GeminiRole = .user
    public var parts: [GeminiPart]
    public var createdAt: Date
    
    public init(parts: [GeminiPart], createdAt: Date = Date()) {
        self.parts = parts
        self.createdAt = createdAt
    }
    
    public init(text: String, createdAt: Date = Date()) {
        self.parts = [.text(GeminiTextPart(text: text))]
        self.createdAt = createdAt
    }
}

public struct GeminiModelMessage: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case role
        case parts
    }
    
    public var role: GeminiRole = .model
    public var parts: [GeminiPart]
    
    public init(parts: [GeminiPart]) {
        self.parts = parts
    }
    
    public init(text: String) {
        self.parts = [.text(GeminiTextPart(text: text))]
    }
}

public enum GeminiMessage: Hashable, Codable, Sendable {
    case user(GeminiUserMessage)
    case model(GeminiModelMessage)
    
    private enum CodingKeys: String, CodingKey {
        case role
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(GeminiRole.self, forKey: .role)
        switch role {
        case .user:
            let message = try GeminiUserMessage(from: decoder)
            self = .user(message)
        case .model:
            let message = try GeminiModelMessage(from: decoder)
            self = .model(message)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .user(let message):
            try message.encode(to: encoder)
        case .model(let message):
            try message.encode(to: encoder)
        }
    }
    
    public var role: GeminiRole {
        switch self {
        case .user:
            return .user
        case .model:
            return .model
        }
    }
    
    public var parts: [GeminiPart] {
        switch self {
        case .user(let message):
            return message.parts
        case .model(let message):
            return message.parts
        }
    }
}

public struct GeminiTool: Codable, Sendable {
    public struct FunctionDeclaration: Codable, Sendable {
        public let name: String
        public let description: String
        public let parameters: JSONSchema?
        
        public init(name: String, description: String, parameters: JSONSchema?) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
    
    public let functionDeclarations: [FunctionDeclaration]
    
    public init(functionDeclarations: [FunctionDeclaration]) {
        self.functionDeclarations = functionDeclarations
    }
}
