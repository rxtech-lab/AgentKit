import Agent
import SwiftUI

public protocol ChatProvider {
    func sendMessage(message: String, model: Model) async throws
}

public enum RenderAction {
    case replace
    case append
    case skip
}

public typealias MessageRenderer = (Message, [Message], ChatProvider?) -> (AnyView, RenderAction)

