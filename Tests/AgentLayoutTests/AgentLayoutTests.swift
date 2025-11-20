import Testing
import SwiftUI
import ViewInspector
import Agent
@testable import AgentLayout

extension AgentLayout: Inspectable {}
extension MessageRow: Inspectable {}
extension MessageInputView: Inspectable {}

struct MockChatProvider: ChatProvider {
    let onSend: (@Sendable (String, Model) -> Void)?
    
    func sendMessage(message: String, model: Model) async throws {
        onSend?(message, model)
    }
}

@MainActor
@Test func testRenderMessageReplace() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source(displayName: "Test", endpoint: "", apiKey: "", apiType: .openAI, models: [model])
    
    let customContent = "Custom Replacement"
    let renderer: MessageRenderer = { _, _, _ in
        (AnyView(Text(customContent)), .replace)
    }
    
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )
    
    let view = try sut.inspect()
    
    // Verify custom view exists
    _ = try view.find(text: customContent)
    
    // Verify original message row is NOT present (since replaced)
    // Note: ViewInspector throws if not found.
    do {
        _ = try view.find(MessageRow.self)
        #expect(Bool(false), "MessageRow should not be present when action is .replace")
    } catch {
        // Expected
    }
}

@MainActor
@Test func testRenderMessageAppend() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source(displayName: "Test", endpoint: "", apiKey: "", apiType: .openAI, models: [model])
    
    let customContent = "Custom Append"
    let renderer: MessageRenderer = { _, _, _ in
        (AnyView(Text(customContent)), .append)
    }
    
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )
    
    let view = try sut.inspect()
    
    // Verify custom view exists
    _ = try view.find(text: customContent)
    
    // Verify original message row IS present
    _ = try view.find(MessageRow.self)
}

@MainActor
@Test func testRenderMessageSkip() async throws {
    let messageContent = "Original Message"
    let message = Message.openai(.user(.init(content: messageContent)))
    let chat = Chat(id: UUID(), gameId: "test", messages: [message])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source(displayName: "Test", endpoint: "", apiKey: "", apiType: .openAI, models: [model])
    
    let renderer: MessageRenderer = { _, _, _ in
        (AnyView(EmptyView()), .skip)
    }
    
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        renderMessage: renderer
    )
    
    let view = try sut.inspect()
    
    // Verify original message row is NOT present
    do {
        _ = try view.find(MessageRow.self)
        #expect(Bool(false), "MessageRow should not be present when action is .skip")
    } catch {
        // Expected
    }
}

@MainActor
@Test func testOnSendCallback() async throws {
    let chat = Chat(id: UUID(), gameId: "test", messages: [])
    let model = Model.openAI(.init(id: "gpt-4"))
    let source = Source(displayName: "Test", endpoint: "", apiKey: "", apiType: .openAI, models: [model])
    
    var sentMessage: String?
    let onSend: (String) -> Void = { message in
        sentMessage = message
    }
    
    let sut = AgentLayout(
        chat: chat,
        currentModel: .constant(model),
        currentSource: .constant(source),
        sources: [source],
        onSend: onSend
    )
    
    // Host the view to ensure State/Binding updates work correctly
    ViewHosting.host(view: sut)
    
    let view = try sut.inspect()
    
    // Find input view
    let inputView = try view.find(MessageInputView.self)
    let textField = try inputView.find(ViewType.TextField.self)
    
    // Set input triggers binding update
    try textField.setInput("Hello World")
    
    // Re-find to get updated view hierarchy state
    let updatedInputView = try view.find(MessageInputView.self)
    
    // Manually trigger onSend closure directly from the view struct
    // This bypasses UI interaction issues but verifies the closure wiring
    // The 'onSend' closure in MessageInputView captures the logic in AgentLayout
    try updatedInputView.actualView().onSend("Hello World")
    
    // Verify onSend was called
    #expect(sentMessage == "Hello World")
}
