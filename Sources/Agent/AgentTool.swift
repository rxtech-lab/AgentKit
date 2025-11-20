import Foundation
import JSONSchema

public struct AgentTool: Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONSchema
    public let execute: @Sendable (String) async throws -> String

    public init(
        name: String, description: String, parameters: JSONSchema,
        execute: @escaping @Sendable (String) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
    }
}
