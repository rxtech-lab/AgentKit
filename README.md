# AgentKit

A Swift implementation of LLM agents with multi-agent support.

## Features

- Multiple agent support
- SwiftUI chat layout implementation
- Multiple LLM model integration
  - OpenAI and OpenAI-compatible APIs
  - Google Gemini API
- Clean, intuitive API design

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/rxtech-lab/AgentKit.git", from: "0.1.0")
]
```

## Supported Models

### OpenAI and Compatible APIs
AgentKit supports OpenAI and any OpenAI-compatible API (such as OpenRouter). Use `ApiType.openAI` for these providers.

### Google Gemini
AgentKit supports Google Gemini models through the official Gemini API (https://ai.google.dev/api). Use `ApiType.gemini` for Gemini models.

## License

AgentKit is available under the MIT license. See the LICENSE file for more info.
