import Foundation
import JSONSchema

public protocol AgentToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: JSONSchema { get }
    var inputType: any Decodable.Type { get }
    func invoke(_ args: String) async throws -> String
}

public struct AgentTool<Input, Output>: AgentToolProtocol {
    public let name: String
    public let description: String
    public let parameters: JSONSchema
    public let execute: @Sendable (Input) async throws -> Output

    public let inputType: any Decodable.Type
    public let outputType: any Encodable.Type

    private let _invoke: @Sendable (String) async throws -> String

    public init(
        name: String, description: String, parameters: JSONSchema,
        execute: @escaping @Sendable (Input) async throws -> Output
    ) where Input: Decodable, Output: Encodable {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
        self.inputType = Input.self
        self.outputType = Output.self

        self._invoke = { args in
            guard let data = args.data(using: .utf8) else {
                throw NSError(
                    domain: "AgentTool", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid arguments encoding"])
            }
            let input = try JSONDecoder().decode(Input.self, from: data)
            let output = try await execute(input)
            let outputData = try JSONEncoder().encode(output)
            return String(data: outputData, encoding: .utf8) ?? ""
        }
    }

    // Fallback for non-Codable types (if needed, though discouraged for agents)
    // Note: If you really need non-Codable tools, you'd need another init,
    // but invoke() would have to trap or throw.

    public func invoke(_ args: String) async throws -> String {
        return try await _invoke(args)
    }
}
