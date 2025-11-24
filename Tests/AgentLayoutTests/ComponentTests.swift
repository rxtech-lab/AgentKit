import MarkdownUI
import SwiftUI
import Testing
import ViewInspector
import XCTest

@testable import Agent
@testable import AgentLayout

// MARK: - Models Tests

@MainActor
struct ModelsTests {

    // MARK: - ApiType Tests

    @Test func testApiTypeRawValue() {
        let apiType = ApiType.openAI
        #expect(apiType.rawValue == "openai")
    }

    // MARK: - Architecture Tests

    @Test func testArchitectureInit() {
        let arch = Architecture(
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            tokenizer: "gpt2"
        )
        #expect(arch.inputModalities == ["text", "image"])
        #expect(arch.outputModalities == ["text"])
        #expect(arch.tokenizer == "gpt2")
    }

    @Test func testArchitectureHashable() {
        let arch1 = Architecture(
            inputModalities: ["text"],
            outputModalities: ["text"],
            tokenizer: "gpt2"
        )
        let arch2 = Architecture(
            inputModalities: ["text"],
            outputModalities: ["text"],
            tokenizer: "gpt2"
        )
        #expect(arch1 == arch2)
        #expect(arch1.hashValue == arch2.hashValue)
    }

    // MARK: - Pricing Tests

    @Test func testPricingInit() {
        let pricing = Pricing(
            prompt: 0.001,
            completion: 0.002,
            image: 0.01,
            request: 0.0,
            inputCacheRead: 0.0001,
            inputCacheWrite: 0.0002,
            webSearch: 0.005,
            internalReasoning: 0.003
        )
        #expect(pricing.prompt == 0.001)
        #expect(pricing.completion == 0.002)
        #expect(pricing.image == 0.01)
        #expect(pricing.request == 0.0)
        #expect(pricing.inputCacheRead == 0.0001)
        #expect(pricing.inputCacheWrite == 0.0002)
        #expect(pricing.webSearch == 0.005)
        #expect(pricing.internalReasoning == 0.003)
    }

    @Test func testPricingHashable() {
        let pricing1 = Pricing(
            prompt: 0.001,
            completion: 0.002,
            image: 0.01,
            request: 0.0,
            inputCacheRead: 0.0001,
            inputCacheWrite: 0.0002,
            webSearch: 0.005,
            internalReasoning: 0.003
        )
        let pricing2 = Pricing(
            prompt: 0.001,
            completion: 0.002,
            image: 0.01,
            request: 0.0,
            inputCacheRead: 0.0001,
            inputCacheWrite: 0.0002,
            webSearch: 0.005,
            internalReasoning: 0.003
        )
        #expect(pricing1 == pricing2)
    }

    // MARK: - OpenAICompatibleModel Tests

    @Test func testOpenAICompatibleModelMinimalInit() {
        let model = OpenAICompatibleModel(id: "gpt-4")
        #expect(model.id == "gpt-4")
        #expect(model.name == nil)
        #expect(model.created == nil)
        #expect(model.description == nil)
    }

    @Test func testOpenAICompatibleModelFullInit() {
        let arch = Architecture(
            inputModalities: ["text"],
            outputModalities: ["text"],
            tokenizer: "gpt2"
        )
        let pricing = Pricing(
            prompt: 0.001,
            completion: 0.002,
            image: 0.0,
            request: 0.0,
            inputCacheRead: 0.0,
            inputCacheWrite: 0.0,
            webSearch: 0.0,
            internalReasoning: 0.0
        )
        let model = OpenAICompatibleModel(
            id: "gpt-4o",
            name: "GPT-4o",
            created: 1234567890,
            description: "Latest model",
            architecture: arch,
            pricing: pricing,
            contextLength: 128000,
            huggingFaceId: "openai/gpt-4o",
            perRequestLimits: ["tokens": "1000"],
            supportedParameters: ["temperature", "top_p"]
        )
        #expect(model.id == "gpt-4o")
        #expect(model.name == "GPT-4o")
        #expect(model.created == 1234567890)
        #expect(model.description == "Latest model")
        #expect(model.architecture == arch)
        #expect(model.pricing == pricing)
        #expect(model.contextLength == 128000)
        #expect(model.huggingFaceId == "openai/gpt-4o")
        #expect(model.perRequestLimits?["tokens"] == "1000")
        #expect(model.supportedParameters == ["temperature", "top_p"])
    }

    @Test func testOpenAICompatibleModelHashable() {
        let model1 = OpenAICompatibleModel(id: "gpt-4")
        let model2 = OpenAICompatibleModel(id: "gpt-4")
        #expect(model1 == model2)
    }

    // MARK: - CustomModel Tests

    @Test func testCustomModelInit() {
        let model = CustomModel(id: "my-custom-model")
        #expect(model.id == "my-custom-model")
    }

    @Test func testCustomModelHashable() {
        let model1 = CustomModel(id: "custom")
        let model2 = CustomModel(id: "custom")
        #expect(model1 == model2)
    }

    // MARK: - Provider Tests

    @Test func testProviderOpenAI() {
        let provider = Provider.openAI
        #expect(provider.id == "openai")
        #expect(provider.rawValue == "openai")
    }

    @Test func testProviderOpenRouter() {
        let provider = Provider.openRouter
        #expect(provider.id == "openrouter")
        #expect(provider.rawValue == "openrouter")
    }

    @Test func testProviderCustom() {
        let provider = Provider.custom("my-provider")
        #expect(provider.id == "my-provider")
        #expect(provider.rawValue == "my-provider")
    }

    @Test func testProviderEquality() {
        let provider1 = Provider.openAI
        let provider2 = Provider.openAI
        #expect(provider1 == provider2)

        let provider3 = Provider.custom("test")
        let provider4 = Provider.custom("test")
        #expect(provider3 == provider4)
    }

    @Test func testProviderAllCases() {
        let cases = Provider.allCases
        #expect(cases.contains("openai"))
        #expect(cases.contains("openrouter"))
        #expect(cases.contains("custom"))
    }

    // MARK: - Model Enum Tests

    @Test func testModelOpenAI() {
        let openAIModel = OpenAICompatibleModel(id: "gpt-4", name: "GPT-4")
        let model = Model.openAI(openAIModel)
        #expect(model.id == "gpt-4")
        #expect(model.displayName == "GPT-4")
    }

    @Test func testModelOpenAIWithoutName() {
        let openAIModel = OpenAICompatibleModel(id: "gpt-4")
        let model = Model.openAI(openAIModel)
        #expect(model.id == "gpt-4")
        #expect(model.displayName == "gpt-4") // Falls back to id
    }

    @Test func testModelCustom() {
        let customModel = CustomModel(id: "my-model")
        let model = Model.custom(customModel)
        #expect(model.id == "my-model")
        #expect(model.displayName == "my-model")
    }

    @Test func testModelHashable() {
        let model1 = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        let model2 = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        #expect(model1 == model2)
    }

    // MARK: - Source Tests

    @Test func testSourceInit() {
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test-key"),
            models: []
        )
        #expect(source.displayName == "OpenAI")
        #expect(source.id == "openai")
        #expect(source.models.isEmpty)
    }

    @Test func testSourceWithModels() {
        let models: [Model] = [
            .openAI(OpenAICompatibleModel(id: "gpt-4")),
            .custom(CustomModel(id: "custom"))
        ]
        let source = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: models
        )
        #expect(source.models.count == 2)
    }

    @Test func testOpenRouterSource() {
        let source = Source.openRouter(
            client: OpenRouterClient(apiKey: "test-key"),
            models: []
        )
        #expect(source.displayName == "OpenRouter")
        #expect(source.id == "openrouter")
    }
}

// MARK: - OpenAIToolMessageRow Tests

@MainActor
struct OpenAIToolMessageRowTests {

    @Test func testToolMessageRowWithResponse() throws {
        let toolCall = OpenAIToolCall(
            id: "call_123",
            type: .function,
            function: .init(name: "get_weather", arguments: "{\"location\": \"NYC\"}")
        )
        let messages: [OpenAIMessage] = [
            .tool(.init(content: "{\"temp\": 72}", toolCallId: "call_123", name: "get_weather"))
        ]

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: messages,
            status: .idle
        )

        let view = try row.inspect()
        let vStack = try view.find(ViewType.VStack.self)
        _ = try vStack.find(ViewType.Button.self)
    }

    @Test func testToolMessageRowLoading() throws {
        let toolCall = OpenAIToolCall(
            id: "call_456",
            type: .function,
            function: .init(name: "search", arguments: "{\"query\": \"test\"}")
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .loading
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolMessageRowNoResponse() throws {
        let toolCall = OpenAIToolCall(
            id: "call_789",
            type: .function,
            function: .init(name: "calculate", arguments: "{}")
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testToolMessageRowWithUnknownFunction() throws {
        let toolCall = OpenAIToolCall(
            id: "call_000",
            type: .function,
            function: nil
        )

        let row = OpenAIToolMessageRow(
            toolCall: toolCall,
            messages: [],
            status: .idle
        )

        let view = try row.inspect()
        _ = try view.find(ViewType.VStack.self)
    }
}

// MARK: - JSONView Tests

@MainActor
struct JSONViewTests {

    @Test func testJSONSyntaxViewValidJSON() throws {
        let view = JSONSyntaxView(jsonString: "{\"key\": \"value\"}")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testJSONSyntaxViewInvalidJSON() throws {
        let view = JSONSyntaxView(jsonString: "not valid json")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testJSONSyntaxViewComplexJSON() throws {
        let json = """
        {"name": "John", "age": 30, "active": true, "data": null, "items": [1, 2, 3]}
        """
        let view = JSONSyntaxView(jsonString: json)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testJSONSyntaxViewEmptyString() throws {
        let view = JSONSyntaxView(jsonString: "")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ZStack.self)
    }

    @Test func testFormattedJSONText() throws {
        let view = FormattedJSONText(jsonString: "{\"key\": \"value\"}")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testFormattedJSONTextWithNumbers() throws {
        let view = FormattedJSONText(jsonString: "  \"count\": 123,\n  \"price\": 45.67")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testFormattedJSONTextWithBoolean() throws {
        let view = FormattedJSONText(jsonString: "  \"active\": true,\n  \"deleted\": false")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testFormattedJSONTextWithNull() throws {
        let view = FormattedJSONText(jsonString: "  \"data\": null")
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    @Test func testJSONTokenType() {
        // Test that all token types exist
        let types: [JSONTokenType] = [.key, .string, .number, .bool, .null, .punctuation, .other]
        #expect(types.count == 7)
    }

    @Test func testJSONToken() {
        let token = JSONToken(id: UUID(), text: "test", type: .string)
        #expect(token.text == "test")
        #expect(token.type == .string)
    }
}

// MARK: - ModelPicker Tests

@MainActor
struct ModelPickerTests {

    @Test func testModelPickerInit() throws {
        var currentModel = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: [.openAI(OpenAICompatibleModel(id: "gpt-4"))]
        )

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: [currentSource],
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }

    @Test func testModelPickerWithMultipleSources() throws {
        var currentModel = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: [.openAI(OpenAICompatibleModel(id: "gpt-4"))]
        )

        let sources = [
            currentSource,
            Source.openRouter(
                client: OpenRouterClient(apiKey: "key2"),
                models: [.openRouter(OpenAICompatibleModel(id: "anthropic/claude-3"))]
            )
        ]

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: sources,
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }

    @Test func testModelPickerWithCustomModel() throws {
        var currentModel = Model.custom(CustomModel(id: "my-model"))
        var currentSource = Source.openAI(
            client: OpenAIClient(apiKey: "key"),
            models: [.custom(CustomModel(id: "my-model"))]
        )

        let picker = ModelPicker(
            currentModel: Binding(get: { currentModel }, set: { currentModel = $0 }),
            currentSource: Binding(get: { currentSource }, set: { currentSource = $0 }),
            sources: [currentSource],
            onClose: {}
        )

        let view = try picker.inspect()
        _ = try view.find(ViewType.ScrollView.self)
    }
}

// MARK: - CodeBlockView Rendering Tests

@MainActor
struct CodeBlockViewRenderingTests {

    @Test func testCodeBlockRendersWithMarkdown() throws {
        // Create a mock configuration using MarkdownUI's types
        let markdown = Markdown("```swift\nlet x = 1\n```")
        let view = try markdown.inspect()
        // CodeBlockView is used internally by MarkdownUI when rendering code blocks
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testCodeBlockWithLongCode() throws {
        let longCode = String(repeating: "let x = 1\n", count: 100)
        let markdown = Markdown("```swift\n\(longCode)```")
        let view = try markdown.inspect()
        _ = try view.find(ViewType.VStack.self)
    }

    @Test func testCodeBlockWithDifferentLanguages() throws {
        // Python
        let pythonMarkdown = Markdown("```python\ndef hello():\n    print('Hello')\n```")
        let pythonView = try pythonMarkdown.inspect()
        _ = try pythonView.find(ViewType.VStack.self)

        // JavaScript
        let jsMarkdown = Markdown("```javascript\nconst x = 1;\n```")
        let jsView = try jsMarkdown.inspect()
        _ = try jsView.find(ViewType.VStack.self)

        // No language specified
        let plainMarkdown = Markdown("```\nplain code\n```")
        let plainView = try plainMarkdown.inspect()
        _ = try plainView.find(ViewType.VStack.self)
    }

    @Test func testMarkdownWithChatTheme() throws {
        let markdown = Markdown("```swift\nlet x = 1\n```")
            .markdownTheme(Theme.chatTheme)
        let view = try markdown.inspect()
        _ = try view.find(ViewType.VStack.self)
    }
}

// MARK: - CopyButton Tests

@MainActor
struct CopyButtonTests {

    @Test func testCopyButtonInit() throws {
        let button = CopyButton(content: "Test content")
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }

    @Test func testCopyButtonWithEmptyContent() throws {
        let button = CopyButton(content: "")
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }

    @Test func testCopyButtonWithLongContent() throws {
        let longContent = String(repeating: "A", count: 10000)
        let button = CopyButton(content: longContent)
        let view = try button.inspect()
        _ = try view.find(ViewType.Button.self)
    }
}

// MARK: - MarkdownTheme Tests

@MainActor
struct MarkdownThemeTests {

    @Test func testColorExtensions() {
        // Test that color extensions are defined and accessible
        let colors: [Color] = [
            Color.text,
            Color.secondaryText,
            Color.tertiaryText,
            Color.background,
            Color.secondaryBackground,
            Color.link,
            Color.border,
            Color.divider,
            Color.checkbox,
            Color.checkboxBackground
        ]

        // Verify all 10 color extensions exist
        #expect(colors.count == 10)
    }

    @Test func testChatThemeExists() {
        // Verify the chat theme can be accessed
        let _ = Theme.chatTheme
        // If we got here without crashing, the theme exists
        #expect(true)
    }
}

// MARK: - ChatStatus Tests

@MainActor
struct ChatStatusTests {

    @Test func testChatStatusIdle() {
        let status = ChatStatus.idle
        #expect(status == .idle)
    }

    @Test func testChatStatusLoading() {
        let status = ChatStatus.loading
        #expect(status == .loading)
    }
}

// MARK: - Additional OpenAI Message Tests

@MainActor
struct OpenAIMessageExtendedTests {

    @Test func testOpenAIMessageContent() {
        let userMessage = OpenAIMessage.user(.init(content: "Hello"))
        #expect(userMessage.content == "Hello")

        let assistantMessage = OpenAIMessage.assistant(.init(content: "Hi", toolCalls: nil, audio: nil, reasoning: nil))
        #expect(assistantMessage.content == "Hi")

        let systemMessage = OpenAIMessage.system(.init(content: "System"))
        #expect(systemMessage.content == "System")

        let toolMessage = OpenAIMessage.tool(.init(content: "Result", toolCallId: "123", name: "tool_name"))
        #expect(toolMessage.content == "Result")
    }

    @Test func testOpenAIMessageRole() {
        let userMessage = OpenAIMessage.user(.init(content: "Hello"))
        #expect(userMessage.role == .user)

        let assistantMessage = OpenAIMessage.assistant(.init(content: "Hi", toolCalls: nil, audio: nil, reasoning: nil))
        #expect(assistantMessage.role == .assistant)

        let systemMessage = OpenAIMessage.system(.init(content: "System"))
        #expect(systemMessage.role == .system)

        let toolMessage = OpenAIMessage.tool(.init(content: "Result", toolCallId: "123", name: "tool_name"))
        #expect(toolMessage.role == .tool)
    }

    @Test func testOpenAIToolCall() {
        let toolCall = OpenAIToolCall(
            index: 0,
            id: "call_123",
            type: .function,
            function: .init(name: "test", arguments: "{}")
        )
        #expect(toolCall.id == "call_123")
        #expect(toolCall.index == 0)
        #expect(toolCall.type == .function)
        #expect(toolCall.function?.name == "test")
        #expect(toolCall.function?.arguments == "{}")
    }
}
