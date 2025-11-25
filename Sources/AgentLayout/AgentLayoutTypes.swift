import Agent
import SwiftUI

public protocol ChatProviderProtocol: Sendable {
    func sendMessage(message: String) async throws
    func sendFunctionResult(id: String, result: any Encodable) async throws
    func rejectFunction(id: String) async throws
}

public enum RenderAction {
    case replace
    case append
    case skip
}

public enum ToolStatus {
    case waitingForResult
    case rejected
    case completed
}

public typealias MessageRenderer = (Message, [Message], ChatProviderProtocol, ToolStatus) -> (AnyView, RenderAction)
