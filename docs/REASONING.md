# Reasoning Tokens

AgentKit supports extended thinking/reasoning tokens for models that support this feature. This allows models to reason through complex problems before providing a response, and preserves the reasoning context across tool calls.

## Overview

When enabled, reasoning allows the model to:
- Think through complex problems step-by-step
- Preserve reasoning context across multiple tool calls
- Provide more accurate and well-thought-out responses

## Automatic Detection

AgentKit automatically enables reasoning for models that support it. If a model's `supportedParameters` includes `"reasoning"`, the default configuration (2000 tokens) is automatically applied.

```swift
// Model with reasoning support - auto-enabled with 2000 tokens
let model = OpenAICompatibleModel(
    id: "anthropic/claude-sonnet-4",
    supportedParameters: ["reasoning", "temperature", "top_p"]
)

// Model without reasoning support - reasoning disabled
let model = OpenAICompatibleModel(
    id: "gpt-4",
    supportedParameters: ["temperature", "top_p"]
)
```

## Custom Configuration

You can override the default reasoning configuration by providing a custom `ReasoningConfig`:

```swift
// Custom reasoning with 4000 tokens
let model = OpenAICompatibleModel(
    id: "anthropic/claude-sonnet-4",
    supportedParameters: ["reasoning"],
    reasoningConfig: ReasoningConfig(maxTokens: 4000)
)
```

## ReasoningConfig

The `ReasoningConfig` struct controls reasoning behavior:

```swift
public struct ReasoningConfig {
    /// Maximum number of tokens to use for reasoning
    public let maxTokens: Int

    /// Default configuration with 2000 tokens
    public static let `default` = ReasoningConfig(maxTokens: 2000)

    public init(maxTokens: Int)
}
```

## How It Works

1. **Request**: When reasoning is enabled, the request includes a `reasoning` parameter with the configured `max_tokens`

2. **Response**: The model returns reasoning content in the `reasoning` field of the assistant message

3. **Preservation**: When tool calls occur, the reasoning content is automatically preserved and sent back in subsequent requests, allowing the model to continue its thought process

## Checking Support

You can check if a model supports reasoning:

```swift
let model = OpenAICompatibleModel(
    id: "anthropic/claude-sonnet-4",
    supportedParameters: ["reasoning"]
)

if model.supportsReasoning {
    print("Model supports reasoning")
}
```

## Accessing Reasoning Content

The reasoning content is available in the assistant message:

```swift
for await part in client.process(messages: messages, model: model, tools: tools) {
    switch part {
    case .message(let message):
        if case .openai(.assistant(let assistantMsg)) = message {
            if let reasoning = assistantMsg.reasoning {
                print("Reasoning: \(reasoning)")
            }
        }
    case .textDelta(let text):
        print(text, terminator: "")
    }
}
```

## Supported Providers

Reasoning is supported by OpenRouter for models that include `"reasoning"` in their `supportedParameters`. This typically includes:

- Anthropic Claude models (claude-sonnet-4, etc.)
- Other models with extended thinking capabilities

Check the model's `supportedParameters` to verify reasoning support.
