//
//  Chat.swift
//
//  Created by Qiwei Li on 5/17/25.
//

import Foundation

public struct Chat: Identifiable, Equatable, Hashable {
    public var id: UUID
    public var gameId: String
    public var messages: [Message]

    public init(id: UUID, gameId: String, messages: [Message]) {
        self.id = id
        self.gameId = gameId
        self.messages = messages
    }
}

public enum ChatStatus {
    case idle
    case loading
}

// MARK: - Generic Message Types

/// Role of a message in the conversation
public enum MessageRole: String, Codable, Sendable, Hashable {
    case user
    case assistant
    case system
    case tool
}

/// A tool call made by the assistant
public struct ToolCall: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String
    
    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Reasoning/thinking content from the assistant
public struct ReasoningContent: Hashable, Codable, Sendable {
    public let text: String?
    public let summary: String?
    
    public init(text: String? = nil, summary: String? = nil) {
        self.text = text
        self.summary = summary
    }
}

/// A user message
public struct UserMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let content: String
    public let createdAt: Date
    
    public init(id: String = UUID().uuidString, content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

/// An assistant message
public struct AssistantMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let reasoning: ReasoningContent?
    
    public init(
        id: String = UUID().uuidString,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        reasoning: ReasoningContent? = nil
    ) {
        self.id = id
        self.content = content
        self.toolCalls = toolCalls
        self.reasoning = reasoning
    }
}

/// A system message
public struct SystemMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let content: String
    
    public init(id: String = UUID().uuidString, content: String) {
        self.id = id
        self.content = content
    }
}

/// A tool result message
public struct ToolMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let toolCallId: String
    public let name: String?
    public let content: String
    
    public init(id: String = UUID().uuidString, toolCallId: String, name: String? = nil, content: String) {
        self.id = id
        self.toolCallId = toolCallId
        self.name = name
        self.content = content
    }
}

/// Generic message type that can represent messages from any provider
public enum GenericMessage: Identifiable, Hashable, Codable, Sendable {
    case user(UserMessage)
    case assistant(AssistantMessage)
    case system(SystemMessage)
    case tool(ToolMessage)
    
    public var id: String {
        switch self {
        case .user(let msg): return msg.id
        case .assistant(let msg): return msg.id
        case .system(let msg): return msg.id
        case .tool(let msg): return msg.id
        }
    }
    
    public var role: MessageRole {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        case .tool: return .tool
        }
    }
    
    public var content: String? {
        switch self {
        case .user(let msg): return msg.content
        case .assistant(let msg): return msg.content
        case .system(let msg): return msg.content
        case .tool(let msg): return msg.content
        }
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case role
        case message
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(MessageRole.self, forKey: .role)
        switch role {
        case .user:
            let msg = try container.decode(UserMessage.self, forKey: .message)
            self = .user(msg)
        case .assistant:
            let msg = try container.decode(AssistantMessage.self, forKey: .message)
            self = .assistant(msg)
        case .system:
            let msg = try container.decode(SystemMessage.self, forKey: .message)
            self = .system(msg)
        case .tool:
            let msg = try container.decode(ToolMessage.self, forKey: .message)
            self = .tool(msg)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let msg):
            try container.encode(MessageRole.user, forKey: .role)
            try container.encode(msg, forKey: .message)
        case .assistant(let msg):
            try container.encode(MessageRole.assistant, forKey: .role)
            try container.encode(msg, forKey: .message)
        case .system(let msg):
            try container.encode(MessageRole.system, forKey: .role)
            try container.encode(msg, forKey: .message)
        case .tool(let msg):
            try container.encode(MessageRole.tool, forKey: .role)
            try container.encode(msg, forKey: .message)
        }
    }
}

// MARK: - OpenAI Conversion Extensions

extension GenericMessage {
    /// Convert from OpenAIMessage to GenericMessage
    public static func from(openAI message: OpenAIMessage) -> GenericMessage {
        switch message {
        case .user(let msg):
            return .user(UserMessage(id: msg.id, content: msg.content, createdAt: msg.createdAt))
        case .assistant(let msg):
            let toolCalls = msg.toolCalls?.compactMap { tc -> ToolCall? in
                guard let id = tc.id, let name = tc.function?.name else { return nil }
                return ToolCall(id: id, name: name, arguments: tc.function?.arguments ?? "{}")
            }
            let reasoning: ReasoningContent?
            if let r = msg.reasoning {
                reasoning = ReasoningContent(text: r, summary: nil)
            } else if let details = msg.reasoningDetails, !details.isEmpty {
                let text = details.compactMap { $0.text }.joined(separator: "\n")
                let summary = details.compactMap { $0.summary }.joined(separator: "\n")
                reasoning = ReasoningContent(
                    text: text.isEmpty ? nil : text,
                    summary: summary.isEmpty ? nil : summary
                )
            } else {
                reasoning = nil
            }
            return .assistant(AssistantMessage(
                id: msg.id,
                content: msg.content,
                toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls,
                reasoning: reasoning
            ))
        case .system(let msg):
            return .system(SystemMessage(id: msg.id, content: msg.content))
        case .tool(let msg):
            return .tool(ToolMessage(id: msg.id, toolCallId: msg.toolCallId, name: msg.name, content: msg.content))
        }
    }
    
    /// Convert to OpenAIMessage
    public func toOpenAI() -> OpenAIMessage {
        switch self {
        case .user(let msg):
            return .user(OpenAIUserMessage(id: msg.id, content: msg.content, createdAt: msg.createdAt))
        case .assistant(let msg):
            let toolCalls = msg.toolCalls?.map { tc in
                OpenAIToolCall(
                    id: tc.id,
                    type: .function,
                    function: .init(name: tc.name, arguments: tc.arguments)
                )
            }
            return .assistant(OpenAIAssistantMessage(
                id: msg.id,
                content: msg.content,
                toolCalls: toolCalls,
                audio: nil,
                reasoning: msg.reasoning?.text
            ))
        case .system(let msg):
            return .system(OpenAISystemMessage(id: msg.id, content: msg.content))
        case .tool(let msg):
            return .tool(OpenAIToolMessage(id: msg.id, content: msg.content, toolCallId: msg.toolCallId, name: msg.name))
        }
    }
}

// MARK: - Message (Wrapper with isUpdating)

public enum Message: Identifiable, Hashable, Sendable, Codable {
    case openai(OpenAIMessage, isUpdating: Bool = false)
    case generic(GenericMessage, isUpdating: Bool = false)

    public var id: String {
        switch self {
        case .openai(let openAIMessage, _):
            switch openAIMessage {
            case .user(let msg): return msg.id
            case .assistant(let msg): return msg.id
            case .system(let msg): return msg.id
            case .tool(let msg): return msg.id
            }
        case .generic(let genericMessage, _):
            return genericMessage.id
        }
    }
    
    /// Whether this message is currently being updated/generated
    public var isUpdating: Bool {
        switch self {
        case .openai(_, let updating): return updating
        case .generic(_, let updating): return updating
        }
    }
    
    /// Creates a copy of this message with the isUpdating flag set to the specified value
    public func withUpdating(_ updating: Bool) -> Message {
        switch self {
        case .openai(let msg, _):
            return .openai(msg, isUpdating: updating)
        case .generic(let msg, _):
            return .generic(msg, isUpdating: updating)
        }
    }
    
    /// Get the generic representation of this message
    public var asGeneric: GenericMessage {
        switch self {
        case .openai(let msg, _):
            return GenericMessage.from(openAI: msg)
        case .generic(let msg, _):
            return msg
        }
    }
    
    /// Get the role of this message
    public var role: MessageRole {
        return asGeneric.role
    }
    
    /// Get the content of this message
    public var content: String? {
        return asGeneric.content
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case isUpdating
    }

    private enum MessageType: String, Codable {
        case openai
        case generic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        let isUpdating = try container.decodeIfPresent(Bool.self, forKey: .isUpdating) ?? false
        switch type {
        case .openai:
            let message = try container.decode(OpenAIMessage.self, forKey: .message)
            self = .openai(message, isUpdating: isUpdating)
        case .generic:
            let message = try container.decode(GenericMessage.self, forKey: .message)
            self = .generic(message, isUpdating: isUpdating)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .openai(let message, let isUpdating):
            try container.encode(MessageType.openai, forKey: .type)
            try container.encode(message, forKey: .message)
            if isUpdating {
                try container.encode(isUpdating, forKey: .isUpdating)
            }
        case .generic(let message, let isUpdating):
            try container.encode(MessageType.generic, forKey: .type)
            try container.encode(message, forKey: .message)
            if isUpdating {
                try container.encode(isUpdating, forKey: .isUpdating)
            }
        }
    }
}

// MARK: - Convenience Initializers

extension Message {
    /// Create a user message
    public static func user(_ content: String, id: String = UUID().uuidString, isUpdating: Bool = false) -> Message {
        return .generic(.user(UserMessage(id: id, content: content)), isUpdating: isUpdating)
    }
    
    /// Create an assistant message
    public static func assistant(
        _ content: String?,
        id: String = UUID().uuidString,
        toolCalls: [ToolCall]? = nil,
        reasoning: ReasoningContent? = nil,
        isUpdating: Bool = false
    ) -> Message {
        return .generic(.assistant(AssistantMessage(
            id: id,
            content: content,
            toolCalls: toolCalls,
            reasoning: reasoning
        )), isUpdating: isUpdating)
    }
    
    /// Create a system message
    public static func system(_ content: String, id: String = UUID().uuidString) -> Message {
        return .generic(.system(SystemMessage(id: id, content: content)), isUpdating: false)
    }
    
    /// Create a tool result message
    public static func tool(
        toolCallId: String,
        content: String,
        name: String? = nil,
        id: String = UUID().uuidString
    ) -> Message {
        return .generic(.tool(ToolMessage(id: id, toolCallId: toolCallId, name: name, content: content)), isUpdating: false)
    }
}
