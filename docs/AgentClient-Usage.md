# AgentClient Usage Guide

This guide explains how to use the AgentClient, Source, and Model types in the AgentLayout package.

## Overview

The agent system is built around three main concepts:
- **Model**: Represents an AI model (OpenAI, OpenRouter, or custom)
- **Source**: Wraps a client with its available models
- **AgentClient**: Orchestrates message processing with tools

## Creating Clients

### OpenAIClient

```swift
import Agent

// Using default OpenAI endpoint
let openAIClient = OpenAIClient(apiKey: "your-api-key")

// Using custom endpoint (e.g., Azure OpenAI or local server)
let customClient = OpenAIClient(
    apiKey: "your-api-key",
    baseURL: URL(string: "https://your-custom-endpoint.com/v1")!
)
```

### OpenRouterClient

```swift
let openRouterClient = OpenRouterClient(
    apiKey: "your-openrouter-key",
    appName: "MyApp",           // Optional: for OpenRouter analytics
    siteURL: "https://myapp.com" // Optional: for OpenRouter analytics
)
```

## Defining Models

Models represent the AI models available for use:

```swift
// OpenAI model
let gpt4 = Model.openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4"))

// OpenRouter model
let claude = Model.openRouter(OpenAICompatibleModel(
    id: "anthropic/claude-3-opus",
    name: "Claude 3 Opus"
))

// Custom model (for custom endpoints)
let customModel = Model.custom(CustomModel(id: "my-custom-model"))
```

## Creating Sources

A Source wraps a client with its available models:

```swift
// OpenAI source with multiple models
let openAISource = Source.openAI(
    client: OpenAIClient(apiKey: "sk-..."),
    models: [
        .openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")),
        .openAI(OpenAICompatibleModel(id: "gpt-4-turbo", name: "GPT-4 Turbo")),
        .openAI(OpenAICompatibleModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo"))
    ]
)

// OpenRouter source
let openRouterSource = Source.openRouter(
    client: OpenRouterClient(apiKey: "or-..."),
    models: [
        .openRouter(OpenAICompatibleModel(id: "anthropic/claude-3-opus")),
        .openRouter(OpenAICompatibleModel(id: "anthropic/claude-3-sonnet")),
        .openRouter(OpenAICompatibleModel(id: "google/gemini-pro"))
    ]
)
```

### Source Properties

```swift
let source = Source.openAI(client: ..., models: [...])

source.id           // "openai" or "openrouter"
source.displayName  // "OpenAI" or "OpenRouter"
source.models       // Array of available models
source.client       // The underlying ChatClient
```

## Processing Messages

### Basic Usage

```swift
let agentClient = AgentClient()

let messages: [Message] = [
    .openai(.system(.init(content: "You are a helpful assistant."))),
    .openai(.user(.init(content: "Hello!")))
]

let stream = await agentClient.process(
    messages: messages,
    model: .openAI(OpenAICompatibleModel(id: "gpt-4")),
    source: openAISource,
    tools: []
)

for try await part in stream {
    switch part {
    case .textDelta(let text):
        // Streaming text chunk
        print(text, terminator: "")
    case .message(let message):
        // Complete message (assistant response, tool result)
        handleMessage(message)
    case .error(let error):
        print("Error: \(error)")
    }
}
```

### With Tools

```swift
// Define a tool
struct WeatherInput: Decodable {
    let location: String
}

let weatherTool = AgentTool(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: .object(
        properties: ["location": .string(description: "City name")],
        required: ["location"]
    )
) { (args: WeatherInput) -> String in
    // Your implementation
    return "Sunny, 72°F in \(args.location)"
}

// Process with tools
let stream = await agentClient.process(
    messages: messages,
    model: currentModel,
    source: currentSource,
    tools: [weatherTool]
)
```

### UI Tools

UI tools pause execution to wait for user interaction:

```swift
let confirmTool = AgentTool(
    name: "confirm_action",
    description: "Ask user for confirmation",
    parameters: .object(
        properties: ["message": .string()],
        required: ["message"]
    ),
    toolType: .ui  // This makes it a UI tool
) { (args: ConfirmInput) -> String in
    return "User confirmed"
}
```

When a UI tool is called, the stream ends without executing the tool, allowing your UI to handle user interaction.

## Using with AgentLayout

```swift
import SwiftUI
import Agent
import AgentLayout

struct ChatView: View {
    @State private var chat = Chat(id: UUID(), gameId: "chat", messages: [])
    @State private var currentModel = Model.openAI(
        OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")
    )
    @State private var currentSource = Source.openAI(
        client: OpenAIClient(apiKey: "your-key"),
        models: [
            .openAI(OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")),
            .openAI(OpenAICompatibleModel(id: "gpt-3.5-turbo", name: "GPT-3.5"))
        ]
    )

    var body: some View {
        AgentLayout(
            chat: chat,
            currentModel: $currentModel,
            currentSource: $currentSource,
            sources: [currentSource],
            tools: [/* your tools */]
        )
    }
}
```

## Model Matching

The AgentClient validates that the model type matches the source type:

- `.openAI` and `.custom` models require `.openAI` source
- `.openRouter` models require `.openRouter` source

```swift
// This works
let stream = await client.process(
    messages: messages,
    model: .openAI(OpenAICompatibleModel(id: "gpt-4")),
    source: Source.openAI(client: ..., models: [...]),
    tools: []
)

// This throws AgentClientError.invalidSource
let stream = await client.process(
    messages: messages,
    model: .openRouter(OpenAICompatibleModel(id: "claude-3")),
    source: Source.openAI(client: ..., models: [...]),  // Wrong source!
    tools: []
)
```

## Error Handling

```swift
do {
    for try await part in stream {
        // Handle parts
    }
} catch let error as AgentClientError {
    switch error {
    case .invalidURL:
        print("Invalid URL in endpoint")
    case .missingCredentials:
        print("Missing API key or endpoint")
    case .invalidSource:
        print("Model type doesn't match source type")
    }
} catch {
    print("Other error: \(error)")
}
```

## Best Practices

1. **Reuse clients**: Create clients once and reuse them across requests
2. **Match models to sources**: Ensure your model type matches the source type
3. **Handle streaming**: Process `textDelta` for real-time updates
4. **Use UI tools wisely**: For user confirmations and interactive elements
5. **Error handling**: Always handle errors in the stream
