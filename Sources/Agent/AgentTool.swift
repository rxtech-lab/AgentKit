import Foundation
import JSONSchema

public protocol AgentToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: JSONSchema { get }
    var inputType: any Decodable.Type { get }

    func invoke(args: any Decodable, originalArgs: String) async throws -> any Encodable
    func invoke(argsData: Data, originalArgs: String) async throws -> any Encodable
}

public struct AgentTool<Input: Decodable & Sendable, Output: Encodable & Sendable>:
    AgentToolProtocol
{
    public let name: String
    public let description: String
    public let parameters: JSONSchema
    public let execute: @Sendable (Input) async throws -> Output

    public var inputType: any Decodable.Type { Input.self }
    public var outputType: any Encodable.Type { Output.self }

    public init(
        name: String, description: String, parameters: JSONSchema,
        execute: @escaping @Sendable (Input) async throws -> Output
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
    }

    public func invoke(args: any Decodable, originalArgs: String) async throws -> any Encodable {
        guard let input = args as? Input else {
            throw ToolError.invalidToolArgs(
                toolName: name, args: originalArgs,
                underlyingError: NSError(
                    domain: "AgentTool", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid arguments type"]))
        }
        return try await execute(input)
    }

    public func invoke(argsData: Data, originalArgs: String) async throws -> any Encodable {
        do {
            let input = try JSONDecoder().decode(Input.self, from: argsData)
            return try await execute(input)
        } catch let error as DecodingError {
            throw ToolError.invalidToolArgs(toolName: name, args: originalArgs, underlyingError: error)
        }
    }
}
