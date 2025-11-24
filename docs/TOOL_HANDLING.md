# AgentLayout Tool Handling and UI Updates

## Overview
This document details the new tool handling mechanisms introduced to `AgentLayout`, specifically focusing on "UI Tools", tool execution status, and user interaction flows including cancellation.

## 1. UI Tools vs. Regular Tools
Tools can now be categorized into two types via the `AgentToolType` enum in `AgentToolProtocol`:

- **`.regular` (Default)**: Executed automatically by the `AgentClient` loop as soon as the model requests them.
- **`.ui`**: When the model requests a UI tool, the automatic execution loop **pauses**. The system waits for a user interaction or client-side event to provide the result externally via the `ChatProvider`.

### Defining a UI Tool
```swift
let uiTool = AgentTool(
    name: "show_confirmation_dialog",
    description: "Ask the user for confirmation",
    parameters: schema,
    toolType: .ui, // Specify this to pause execution
    execute: { input in ... }
)
```

## 2. Tool Status for Rendering
The `MessageRenderer` closure now receives a `ToolStatus` enum as its fourth argument. This allows custom views to react to the state of a tool call.

### Statuses
- **`.waitingForResult`**: The assistant has requested a tool call, but no corresponding tool result message exists in the chat history yet.
- **`.rejected`**: The tool call has a result, but it matches the rejection criteria (content is "User cancelled this tool call").
- **`.completed`**: The tool call has been successfully resolved with a result.

### Usage Example
```swift
AgentLayout(
    // ...
    renderMessage: { message, allMessages, provider, status in
        if status == .waitingForResult {
            return (AnyView(ProgressView()), .append)
        }
        // ...
    }
)
```

## 3. ChatProvider Updates
The `ChatProvider` protocol has been expanded to support explicit function result handling and rejection:

```swift
public protocol ChatProvider: Sendable {
    func sendMessage(message: String, model: Model) async throws
    
    /// Send a result for a specific tool call ID to the backend/agent
    func sendFunctionResult(id: String, result: any Encodable) async throws
    
    /// Reject or cancel a specific tool call ID
    func rejectFunction(id: String) async throws
}
```

## 4. Cancellation Behavior

### Streaming Cancellation
If the user clicks the stop button while a message is being generated (streaming):
1. The internal `generationTask` is cancelled immediately.
2. A partial message (if any) is preserved.
3. A new **User Message** with the content `"Cancelled"` is appended to the chat to indicate the interruption.

### Tool Call Cancellation
If the user clicks the stop/cancel button while the system is paused waiting for a UI tool result:
1. The `chatProvider.rejectFunction(id:)` method is called for the pending tool call.
2. A **Tool Message** with the content `"User cancelled this tool call"` is appended to the chat.
3. This triggers the `.rejected` status for that tool call.

## 5. UI Components
- **MessageInputView**: The text input field is now **disabled** whenever the chat status is `.loading`. This includes both active streaming and waiting for a tool result.

