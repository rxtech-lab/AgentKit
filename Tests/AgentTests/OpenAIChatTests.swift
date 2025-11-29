import Foundation
import JSONSchema
import Testing

@testable import Agent

@MainActor
struct OpenAIChatTests {

    // MARK: - OpenAIRole Tests

    @Test func testOpenAIRoleRawValues() {
        #expect(OpenAIRole.user.rawValue == "user")
        #expect(OpenAIRole.assistant.rawValue == "assistant")
        #expect(OpenAIRole.tool.rawValue == "tool")
        #expect(OpenAIRole.system.rawValue == "system")
    }

    // MARK: - OpenAIContentType Tests

    @Test func testOpenAIContentTypeRawValues() {
        #expect(OpenAIContentType.text.rawValue == "text")
        #expect(OpenAIContentType.image.rawValue == "image")
        #expect(OpenAIContentType.audio.rawValue == "audio")
    }

    // MARK: - OpenAITextContentPart Tests

    @Test func testOpenAITextContentPartInit() {
        let part = OpenAITextContentPart(text: "Hello world")
        #expect(part.text == "Hello world")
        #expect(part.type == .text)
    }

    @Test func testOpenAITextContentPartCodable() throws {
        let part = OpenAITextContentPart(text: "Test")
        let encoded = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(OpenAITextContentPart.self, from: encoded)
        #expect(decoded.text == "Test")
        #expect(decoded.type == .text)
    }

    // MARK: - OpenAIImageContentPart Tests

    @Test func testOpenAIImageContentPartInit() {
        let imageUrl = OpenAIImageContentPart.ImageUrl(
            url: "https://example.com/image.png", detail: .high)
        let part = OpenAIImageContentPart(imageUrl: imageUrl)
        #expect(part.imageUrl.url == "https://example.com/image.png")
        #expect(part.imageUrl.detail == .high)
        #expect(part.type == .image)
    }

    @Test func testOpenAIImageUrlDetailTypes() {
        #expect(OpenAIImageContentPart.ImageUrl.Detail.auto.rawValue == "auto")
        #expect(OpenAIImageContentPart.ImageUrl.Detail.low.rawValue == "low")
        #expect(OpenAIImageContentPart.ImageUrl.Detail.high.rawValue == "high")
    }

    @Test func testOpenAIImageContentPartCodable() throws {
        let imageUrl = OpenAIImageContentPart.ImageUrl(
            url: "https://example.com/image.png", detail: .auto)
        let part = OpenAIImageContentPart(imageUrl: imageUrl)
        let encoded = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(OpenAIImageContentPart.self, from: encoded)
        #expect(decoded.imageUrl.url == "https://example.com/image.png")
        #expect(decoded.imageUrl.detail == .auto)
    }

    // MARK: - OpenAIAudioContentPart Tests

    @Test func testOpenAIAudioContentPartInit() {
        let inputAudio = OpenAIAudioContentPart.InputAudio(data: "base64data", format: .wav)
        let part = OpenAIAudioContentPart(inputAudio: inputAudio)
        #expect(part.inputAudio.data == "base64data")
        #expect(part.inputAudio.format == .wav)
        #expect(part.type == .audio)
    }

    @Test func testOpenAIInputAudioFormats() {
        #expect(OpenAIAudioContentPart.InputAudio.Format.wav.rawValue == "wav")
        #expect(OpenAIAudioContentPart.InputAudio.Format.mp3.rawValue == "mp3")
    }

    @Test func testOpenAIAudioContentPartCodable() throws {
        let inputAudio = OpenAIAudioContentPart.InputAudio(data: "test", format: .mp3)
        let part = OpenAIAudioContentPart(inputAudio: inputAudio)
        let encoded = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(OpenAIAudioContentPart.self, from: encoded)
        #expect(decoded.inputAudio.data == "test")
        #expect(decoded.inputAudio.format == .mp3)
    }

    // MARK: - OpenAIContent Tests

    @Test func testOpenAIContentText() {
        let content = OpenAIContent.text("Hello")
        if case .text(let text) = content {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func testOpenAIContentTextCodable() throws {
        let content = OpenAIContent.text("Test message")
        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(OpenAIContent.self, from: encoded)
        if case .text(let text) = decoded {
            #expect(text == "Test message")
        } else {
            Issue.record("Expected text content")
        }
    }

    // MARK: - OpenAIToolCall Tests

    @Test func testOpenAIToolCallInit() {
        let toolCall = OpenAIToolCall(
            index: 0,
            id: "call_123",
            type: .function,
            function: .init(name: "get_weather", arguments: "{\"location\": \"NYC\"}")
        )
        #expect(toolCall.index == 0)
        #expect(toolCall.id == "call_123")
        #expect(toolCall.type == .function)
        #expect(toolCall.function?.name == "get_weather")
        #expect(toolCall.function?.arguments == "{\"location\": \"NYC\"}")
    }

    @Test func testOpenAIToolCallMinimalInit() {
        let toolCall = OpenAIToolCall(id: nil, type: nil, function: nil)
        #expect(toolCall.id == nil)
        #expect(toolCall.type == nil)
        #expect(toolCall.function == nil)
        #expect(toolCall.index == nil)
    }

    @Test func testOpenAIToolCallCodable() throws {
        let toolCall = OpenAIToolCall(
            index: 1,
            id: "call_456",
            type: .function,
            function: .init(name: "search", arguments: "{}")
        )
        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(OpenAIToolCall.self, from: encoded)
        #expect(decoded.id == "call_456")
        #expect(decoded.index == 1)
        #expect(decoded.function?.name == "search")
    }

    @Test func testOpenAIToolCallToolType() {
        #expect(OpenAIToolCall.ToolType.function.rawValue == "function")
    }

    // MARK: - OpenAIUserMessage Tests

    @Test func testOpenAIUserMessageInit() {
        let message = OpenAIUserMessage(content: "Hello")
        #expect(message.content == "Hello")
        #expect(message.role == .user)
        #expect(!message.id.isEmpty)
    }

    @Test func testOpenAIUserMessageWithId() {
        let message = OpenAIUserMessage(id: "custom-id", content: "Test")
        #expect(message.id == "custom-id")
        #expect(message.content == "Test")
    }

    @Test func testOpenAIUserMessageCodable() throws {
        let message = OpenAIUserMessage(id: "msg-1", content: "User message")
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(OpenAIUserMessage.self, from: encoded)
        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        #expect(decoded.content == "User message")
        #expect(decoded.role == .user)
    }

    @Test func testOpenAIUserMessageDecodingWithoutOptionals() throws {
        let json = """
            {"content": "Test message"}
            """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OpenAIUserMessage.self, from: data)
        #expect(decoded.content == "Test message")
        #expect(decoded.role == .user)
        #expect(!decoded.id.isEmpty)
    }

    // MARK: - OpenAIAssistantMessage Tests

    @Test func testOpenAIAssistantMessageInit() {
        let message = OpenAIAssistantMessage(content: "Hello", toolCalls: nil, audio: nil)
        #expect(message.content == "Hello")
        #expect(message.role == .assistant)
        #expect(message.toolCalls == nil)
        #expect(message.audio == nil)
    }

    @Test func testOpenAIAssistantMessageWithToolCalls() {
        let toolCalls = [
            OpenAIToolCall(
                id: "call_1", type: .function, function: .init(name: "test", arguments: "{}"))
        ]
        let message = OpenAIAssistantMessage(content: nil, toolCalls: toolCalls, audio: nil)
        #expect(message.content == nil)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.id == "call_1")
    }

    @Test func testOpenAIAssistantMessageWithAudio() {
        let audio = OpenAIAssistantMessage.Audio(id: "audio-1", data: "base64", transcript: "Hello")
        let message = OpenAIAssistantMessage(content: "Test", toolCalls: nil, audio: audio)
        #expect(message.audio?.id == "audio-1")
        #expect(message.audio?.data == "base64")
        #expect(message.audio?.transcript == "Hello")
    }

    @Test func testOpenAIAssistantMessageCodable() throws {
        let message = OpenAIAssistantMessage(
            id: "msg-1", content: "Response", toolCalls: nil, audio: nil)
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(OpenAIAssistantMessage.self, from: encoded)
        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        #expect(decoded.content == "Response")
        #expect(decoded.role == .assistant)
    }

    @Test func testOpenAIAssistantMessageToRequestMessage() {
        let audio = OpenAIAssistantMessage.Audio(id: "audio-1", data: "base64", transcript: "Hello")
        let message = OpenAIAssistantMessage(
            id: "msg-1", content: "Test", toolCalls: nil, audio: audio)
        let requestMessage = message.toRequestAssistantMessage()
        #expect(requestMessage.id == "msg-1")
        #expect(requestMessage.content == "Test")
        #expect(requestMessage.audio == nil)  // Audio should be dropped
    }

    // MARK: - OpenAISystemMessage Tests

    @Test func testOpenAISystemMessageInit() {
        let message = OpenAISystemMessage(content: "You are a helpful assistant")
        #expect(message.content == "You are a helpful assistant")
        #expect(message.role == .system)
        #expect(!message.id.isEmpty)
    }

    @Test func testOpenAISystemMessageWithId() {
        let message = OpenAISystemMessage(id: "sys-1", content: "System prompt")
        #expect(message.id == "sys-1")
        #expect(message.content == "System prompt")
    }

    @Test func testOpenAISystemMessageCodable() throws {
        let message = OpenAISystemMessage(id: "sys-1", content: "Be helpful")
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(OpenAISystemMessage.self, from: encoded)
        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        #expect(decoded.content == "Be helpful")
        #expect(decoded.role == .system)
    }

    // MARK: - OpenAIToolMessage Tests

    @Test func testOpenAIToolMessageInit() {
        let message = OpenAIToolMessage(content: "Result", toolCallId: "call_123")
        #expect(message.content == "Result")
        #expect(message.toolCallId == "call_123")
        #expect(message.role == .tool)
        #expect(!message.id.isEmpty)
    }

    @Test func testOpenAIToolMessageWithId() {
        let message = OpenAIToolMessage(id: "tool-msg-1", content: "Data", toolCallId: "call_456")
        #expect(message.id == "tool-msg-1")
        #expect(message.content == "Data")
        #expect(message.toolCallId == "call_456")
    }

    @Test func testOpenAIToolMessageCodable() throws {
        let message = OpenAIToolMessage(
            id: "tool-1", content: "{\"result\": 42}", toolCallId: "call_789")
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(OpenAIToolMessage.self, from: encoded)
        // ID is not encoded (excluded for API compatibility), so a new one is generated on decode
        #expect(!decoded.id.isEmpty)
        #expect(decoded.content == "{\"result\": 42}")
        #expect(decoded.toolCallId == "call_789")
        #expect(decoded.role == .tool)
    }

    // MARK: - OpenAIMessage Enum Tests

    @Test func testOpenAIMessageUserCase() {
        let userMsg = OpenAIUserMessage(content: "Hello")
        let message = OpenAIMessage.user(userMsg)
        #expect(message.role == .user)
        #expect(message.content == "Hello")
    }

    @Test func testOpenAIMessageAssistantCase() {
        let assistantMsg = OpenAIAssistantMessage(content: "Hi there", toolCalls: nil, audio: nil)
        let message = OpenAIMessage.assistant(assistantMsg)
        #expect(message.role == .assistant)
        #expect(message.content == "Hi there")
    }

    @Test func testOpenAIMessageSystemCase() {
        let systemMsg = OpenAISystemMessage(content: "Be helpful")
        let message = OpenAIMessage.system(systemMsg)
        #expect(message.role == .system)
        #expect(message.content == "Be helpful")
    }

    @Test func testOpenAIMessageToolCase() {
        let toolMsg = OpenAIToolMessage(content: "Result", toolCallId: "call_1")
        let message = OpenAIMessage.tool(toolMsg)
        #expect(message.role == .tool)
        #expect(message.content == "Result")
    }

    @Test func testOpenAIMessageEncodeDecode() throws {
        // User message
        let userMessage = OpenAIMessage.user(.init(id: "u1", content: "User"))
        let userEncoded = try JSONEncoder().encode(userMessage)
        let userDecoded = try JSONDecoder().decode(OpenAIMessage.self, from: userEncoded)
        #expect(userDecoded.role == .user)
        #expect(userDecoded.content == "User")

        // Assistant message
        let assistantMessage = OpenAIMessage.assistant(
            .init(id: "a1", content: "Assistant", toolCalls: nil, audio: nil))
        let assistantEncoded = try JSONEncoder().encode(assistantMessage)
        let assistantDecoded = try JSONDecoder().decode(OpenAIMessage.self, from: assistantEncoded)
        #expect(assistantDecoded.role == .assistant)
        #expect(assistantDecoded.content == "Assistant")

        // System message
        let systemMessage = OpenAIMessage.system(.init(id: "s1", content: "System"))
        let systemEncoded = try JSONEncoder().encode(systemMessage)
        let systemDecoded = try JSONDecoder().decode(OpenAIMessage.self, from: systemEncoded)
        #expect(systemDecoded.role == .system)
        #expect(systemDecoded.content == "System")

        // Tool message
        let toolMessage = OpenAIMessage.tool(.init(id: "t1", content: "Tool", toolCallId: "call_1"))
        let toolEncoded = try JSONEncoder().encode(toolMessage)
        let toolDecoded = try JSONDecoder().decode(OpenAIMessage.self, from: toolEncoded)
        #expect(toolDecoded.role == .tool)
        #expect(toolDecoded.content == "Tool")
    }
    // MARK: - OpenAITool Tests

    @Test func testOpenAIToolInit() throws {
        let schemaJson = """
            {
                "type": "object",
                "properties": {
                    "location": {"type": "string", "description": "City name"}
                },
                "required": ["location"]
            }
            """
        let schema = try JSONSchema(jsonString: schemaJson)
        let tool = OpenAITool(
            name: "get_weather",
            description: "Get weather for a location",
            parameters: schema
        )
        #expect(tool.name == "get_weather")
        #expect(tool.description == "Get weather for a location")
        #expect(tool.strict == false)
    }

    @Test func testOpenAIToolWithStrict() throws {
        let schemaJson = """
            {"type": "object"}
            """
        let schema = try JSONSchema(jsonString: schemaJson)
        let tool = OpenAITool(
            name: "test_tool",
            description: "A test tool",
            parameters: schema,
            strict: true
        )
        #expect(tool.strict == true)
    }

    // MARK: - Message Encoding Tests (ID Exclusion)

    @Test func testOpenAIUserMessageEncodingExcludesId() throws {
        let message = OpenAIUserMessage(id: "test-id-123", content: "Hello")
        let encoded = try JSONEncoder().encode(message)
        let jsonDict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // ID should NOT be included in encoded JSON (OpenAI API doesn't accept it)
        #expect(jsonDict["id"] == nil, "id field should not be encoded")
        #expect(jsonDict["createdAt"] == nil, "createdAt field should not be encoded")
        #expect(jsonDict["role"] as? String == "user")
        #expect(jsonDict["content"] as? String == "Hello")
    }

    @Test func testOpenAIAssistantMessageEncodingExcludesId() throws {
        let message = OpenAIAssistantMessage(
            id: "test-id-456",
            content: "Response",
            toolCalls: nil,
            audio: nil,
            reasoning: "Some reasoning",
            reasoningDetails: nil
        )
        let encoded = try JSONEncoder().encode(message)
        let jsonDict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // ID and response-only fields should NOT be included
        #expect(jsonDict["id"] == nil, "id field should not be encoded")
        #expect(jsonDict["audio"] == nil, "audio field should not be encoded")
        #expect(jsonDict["reasoning"] != nil, "reasoning field should not be encoded")
        #expect(
            jsonDict["reasoning_details"] == nil, "reasoning_details field should not be encoded")
        #expect(jsonDict["role"] as? String == "assistant")
        #expect(jsonDict["content"] as? String == "Response")
    }

    @Test func testOpenAISystemMessageEncodingExcludesId() throws {
        let message = OpenAISystemMessage(id: "test-id-789", content: "System prompt")
        let encoded = try JSONEncoder().encode(message)
        let jsonDict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // ID should NOT be included
        #expect(jsonDict["id"] == nil, "id field should not be encoded")
        #expect(jsonDict["role"] as? String == "system")
        #expect(jsonDict["content"] as? String == "System prompt")
    }

    @Test func testOpenAIToolMessageEncodingExcludesId() throws {
        let message = OpenAIToolMessage(
            id: "test-id-abc",
            content: "Tool result",
            toolCallId: "call_123",
            name: "my_tool"
        )
        let encoded = try JSONEncoder().encode(message)
        let jsonDict = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        // ID should NOT be included, but toolCallId should be
        #expect(jsonDict["id"] == nil, "id field should not be encoded")
        #expect(jsonDict["role"] as? String == "tool")
        #expect(jsonDict["content"] as? String == "Tool result")
        #expect(jsonDict["tool_call_id"] as? String == "call_123")
        #expect(jsonDict["name"] as? String == "my_tool")
    }
}
