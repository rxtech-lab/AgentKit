# AgentKit

A Swift implementation of LLM agents with multi-agent support.

## Features

- Multiple agent support (OpenAI, OpenRouter, Custom Agents)
- SwiftUI chat layout implementation
- Multiple LLM model integration
- Custom agent support for external message handling
- Tool calling with automatic execution
- Reasoning/thinking token support
- Clean, intuitive API design

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/rxtech-lab/AgentKit.git", from: "0.1.0")
]
```

## Usage

### Basic Setup

```swift
import Agent
import AgentLayout

// Create a chat provider
let chatProvider = ChatProvider()

// Define your sources
let openAISource = Source.openAI(
    client: OpenAIClient(apiKey: "your-api-key"),
    models: [.openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4"))]
)

// Create the chat view
AgentLayout(
    chatProvider: chatProvider,
    chat: chat,
    currentModel: $currentModel,
    currentSource: $currentSource,
    sources: [openAISource],
    systemPrompt: "You are a helpful assistant."
)
```

### Custom Agents

Custom agents allow you to add models to the picker that don't use the built-in agent loop. Instead, you handle message generation externally.

```swift
// Define a custom agent
let customAgent = Model.customAgent(CustomAgentModel(id: "my-agent", name: "My Custom Agent"))

// Create a custom agent source
let customSource = Source.customAgent(
    id: "custom-agents",
    displayName: "Custom Agents",
    models: [customAgent]
)

// Set up AgentLayout with custom agent callback
AgentLayout(
    chatProvider: chatProvider,
    chat: chat,
    currentModel: $currentModel,
    currentSource: $currentSource,
    sources: [openAISource, customSource],
    onCustomAgentSend: { userMessage, messages in
        // Handle the message externally
        // Create an assistant message with isUpdating: true to show loading state
        let assistantMsg = Message.openai(
            .assistant(.init(content: "")),
            isUpdating: true
        )
        chatProvider.appendMessage(assistantMsg)
        chatProvider.setStatus(.loading)
        
        // Stream or update the message content
        // ...
        
        // When done, update the message with final content
        chatProvider.updateMessage(
            id: assistantMsg.id,
            with: Message.openai(
                .assistant(.init(content: "Final response")),
                isUpdating: false
            )
        )
        chatProvider.setStatus(.idle)
    }
)
```

### Message Updates for Custom Agents

The `ChatProvider` provides several methods for external message management:

```swift
// Replace all messages
chatProvider.updateMessages(newMessages)

// Append a single message
chatProvider.appendMessage(message)

// Update a specific message by ID (useful for streaming)
chatProvider.updateMessage(id: messageId, with: updatedMessage)

// Set loading/idle status
chatProvider.setStatus(.loading)
chatProvider.setStatus(.idle)
```

### Message isUpdating Property

Messages have an `isUpdating` property to track which message is currently being generated:

```swift
// Create a message that's being updated
let message = Message.openai(.assistant(.init(content: "Partial...")), isUpdating: true)

// Check if a message is updating
if message.isUpdating {
    // Show loading indicator
}

// Create a copy with different updating state
let finishedMessage = message.withUpdating(false)
```

### Custom Message Rendering

You can customize how messages are rendered using the `renderMessage` parameter:

```swift
AgentLayout(
    chatProvider: chatProvider,
    chat: chat,
    currentModel: $currentModel,
    currentSource: $currentSource,
    sources: [source],
    renderMessage: { message, allMessages, provider, toolStatus in
        // Check if this is a message you want to customize
        if message.role == .assistant {
            return (AnyView(MyCustomAssistantView(message: message)), .replace)
        }
        
        // Use default rendering for other messages
        return (AnyView(EmptyView()), .skip)
    }
)
```

The `RenderAction` enum controls how your custom view is used:
- `.replace` - Replace the default message view entirely with your custom view
- `.append` - Show the default message view, then append your custom view after it
- `.skip` - Use default rendering only (your view is ignored)

The callback provides:
- `message` - The current message being rendered
- `allMessages` - All messages in the conversation
- `provider` - The `ChatProviderProtocol` for sending responses
- `toolStatus` - Status of any tool calls (`.waitingForResult`, `.rejected`, `.completed`)

> **Note:** Custom tool rendering is not currently supported. Tool calls are displayed with a default expandable UI showing the tool name, arguments, and response.

### Tools

Define tools that the agent can call:

```swift
struct WeatherInput: Decodable {
    let location: String
}

let weatherTool = AgentTool(
    name: "get_weather",
    description: "Get weather for a location",
    parameters: .object(properties: ["location": .string()], required: ["location"])
) { (args: WeatherInput) in
    return "Sunny in \(args.location)"
}

// Add tools to AgentLayout
AgentLayout(
    chatProvider: chatProvider,
    chat: chat,
    currentModel: $currentModel,
    currentSource: $currentSource,
    sources: [source],
    tools: [weatherTool]
)
```

## Documentation

- [AgentClient Usage](docs/AgentClient-Usage.md)
- [Tool Handling](docs/TOOL_HANDLING.md)
- [Reasoning Support](docs/REASONING.md)

## License

AgentKit is available under the MIT license. See the LICENSE file for more info.
