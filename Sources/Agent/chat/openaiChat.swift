import Foundation

public enum OpenAIRole: String, Codable {
    case user
    case assistant
    case tool
    case system
}

public struct OpenAIMessage: Hashable {
    public var id: String
    public var role: OpenAIRole
    public var content: String
    public var createdAt: Date

    public init(role: OpenAIRole, content: String) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.createdAt = Date()
    }

    public init(id: String, role: OpenAIRole, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
