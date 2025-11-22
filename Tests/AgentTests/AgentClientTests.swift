import Vapor
import XCTest

@testable import Agent

final class AgentClientTests: XCTestCase {
    var app: Application!
    var controller: OpenAIChatController!
    var source: Source!
    var agentClient: AgentClient!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        controller = await OpenAIChatController()
        await controller.registerRoutes(on: app)
        let port = 8124
        app.http.server.configuration.port = port
        try await app.startup()

        source = Source(
            displayName: "Test", endpoint: "http://localhost:\(port)", apiKey: "test",
            apiType: .openAI)
        agentClient = AgentClient()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        controller = nil
    }

    func testMultiTurnConversationWithTools() async throws {
        // 1. Setup Tools
        struct WeatherInput: Decodable {
            let location: String
        }

        let weatherTool = AgentTool(
            name: "get_weather",
            description: "Get weather",
            parameters: .object(properties: ["location": .string()], required: ["location"])
        ) { (args: WeatherInput) in
            return "Sunny in Paris"
        }

        // 2. Setup Mocks
        // Turn 1: Tool Call (split into chunks to test accumulation)
        let delta1 = OpenAIToolCall(
            index: 0,
            id: "call_1",
            type: .function,
            function: .init(name: "get_weather", arguments: "")
        )
        let delta2 = OpenAIToolCall(
            index: 0,
            id: nil,
            type: nil,
            function: .init(name: nil, arguments: "{\"location\": \"Paris\"}")
        )

        let msg1Part1 = OpenAIAssistantMessage(content: nil, toolCalls: [delta1], audio: nil)
        let msg1Part2 = OpenAIAssistantMessage(content: nil, toolCalls: [delta2], audio: nil)

        // Turn 2: Final Answer
        let msg2 = OpenAIAssistantMessage(
            content: "It is sunny in Paris.", toolCalls: nil, audio: nil)

        await controller.mockChatResponse([msg1Part1, msg1Part2])
        await controller.mockChatResponse([msg2])

        // 3. Run Agent
        let stream = await agentClient.process(
            messages: [.openai(.user(.init(content: "Weather in Paris?")))],
            model: "gpt-4",
            tools: [weatherTool],
            source: source
        )

        var receivedContent = ""
        var messageCount = 0

        for try await part in stream {
            switch part {
            case .textDelta(let text):
                receivedContent += text
            case .message(let msg):
                messageCount += 1
                if case .openai(let openAIMsg) = msg {
                    if case .assistant(let a) = openAIMsg, let content = a.content {
                        print("Assistant Message: \(content)")
                    }
                    if case .tool(let t) = openAIMsg {
                        print("Tool Result: \(t.content)")
                    }
                }
            default:
                break
            }
        }

        // 4. Assertions
        XCTAssertTrue(receivedContent.contains("It is sunny in Paris."))
        // messageCount should include:
        // 1. Assistant message (tool call)
        // 2. Tool message (result)
        // 3. Assistant message (final answer)
        XCTAssertGreaterThanOrEqual(messageCount, 3)
    }

    func testToolCallWithInvalidArguments() async throws {
        // 1. Setup Tool (Define Input Type implicitly via closure)
        struct WeatherInput: Decodable {
            let location: String
        }

        let weatherTool = AgentTool(
            name: "get_weather",
            description: "Get weather",
            parameters: .object(properties: ["location": .string()], required: ["location"])
        ) { (args: WeatherInput) in
            return "Sunny in Paris"
        }

        // 2. Setup Mocks
        // The tool call has invalid JSON (missing required field "location")
        let invalidToolCall = OpenAIToolCall(
            index: 0,
            id: "call_bad",
            type: .function,
            function: .init(name: "get_weather", arguments: "{\"wrong_param\": \"Paris\"}")
        )

        let msg1 = OpenAIAssistantMessage(content: nil, toolCalls: [invalidToolCall], audio: nil)
        let msg2 = OpenAIAssistantMessage(
            content: "I need the location.", toolCalls: nil, audio: nil)

        await controller.mockChatResponse([msg1])
        await controller.mockChatResponse([msg2])

        // 3. Run Agent
        let stream = await agentClient.process(
            messages: [.openai(.user(.init(content: "Weather in Paris?")))],
            model: "gpt-4",
            tools: [weatherTool],
            source: source
        )

        var toolErrorMessageFound = false

        for try await part in stream {
            if case .message(let msg) = part,
                case .openai(let openAIMsg) = msg,
                case .tool(let toolMsg) = openAIMsg
            {
                if toolMsg.toolCallId == "call_bad" {
                    // Check if content contains error about decoding or key not found
                    if toolMsg.content.contains("Error:")
                        && toolMsg.content.contains("Please fix the arguments and try again.")
                    {
                        toolErrorMessageFound = true
                    }
                }
            }
        }

        XCTAssertTrue(toolErrorMessageFound, "Should have received a tool message with error")
    }

    func testToolCallWithEncodingError() async throws {
        // 1. Setup Tool
        struct WeatherInput: Decodable { let location: String }
        let weatherTool = AgentTool(
            name: "get_weather",
            description: "Get weather",
            parameters: .object(properties: ["location": .string()], required: ["location"])
        ) { (args: WeatherInput) in return "Sunny" }

        // 2. Setup Mock with invalid UTF8
        // Note: Swift Strings are unicode correct, so hard to force invalid utf8 via string.
        // However, processToolCall checks argumentsString.data(using: .utf8).
        // If toolCall.function?.arguments is nil, it defaults to "{}".
        // We can't easily inject invalid UTF8 via the String type in OpenAIToolCall.
        // But we can test the empty arguments case defaulting to "{}" which is valid JSON.
        // The guard else { throw invalidArgsEncoding } is technically unreachable for valid Swift Strings
        // unless the string contains unpaired surrogates that fail UTF8 encoding,
        // which Swift generally prevents or handles.
        // We'll skip forcing the encoding error for now as it's hard to reach with standard String types.
    }

    func testToolNotFound() async throws {
        // 1. Setup Tools (Empty)
        let tools: [AgentTool<String, String>] = []

        // 2. Setup Mock
        let toolCall = OpenAIToolCall(
            index: 0, id: "call_missing", type: .function,
            function: .init(name: "missing_tool", arguments: "{}")
        )

        let msg1 = OpenAIAssistantMessage(content: nil, toolCalls: [toolCall], audio: nil)
        let msg2 = OpenAIAssistantMessage(content: "Tool not found.", toolCalls: nil, audio: nil)

        await controller.mockChatResponse([msg1])
        await controller.mockChatResponse([msg2])

        // 3. Run Agent
        let stream = await agentClient.process(
            messages: [.openai(.user(.init(content: "Run missing tool")))],
            model: "gpt-4",
            tools: tools,
            source: source
        )

        var toolErrorFound = false
        for try await part in stream {
            if case .message(let msg) = part,
                case .openai(let openAIMsg) = msg,
                case .tool(let toolMsg) = openAIMsg
            {
                if toolMsg.toolCallId == "call_missing" {
                    if toolMsg.content.contains("Tool missing_tool not found") {
                        toolErrorFound = true
                    }
                }
            }
        }
        XCTAssertTrue(toolErrorFound)
    }

    func testGenericToolExecutionError() async throws {
        // 1. Setup Tool that throws
        struct Input: Decodable { let val: String }
        let throwingTool = AgentTool(
            name: "throwing_tool",
            description: "Throws error",
            parameters: .object(properties: [:], required: [])
        ) { (args: Input) -> String in
            throw NSError(
                domain: "Test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        }

        // 2. Setup Mock
        let toolCall = OpenAIToolCall(
            index: 0, id: "call_error", type: .function,
            function: .init(name: "throwing_tool", arguments: "{\"val\": \"a\"}")
        )

        let msg1 = OpenAIAssistantMessage(content: nil, toolCalls: [toolCall], audio: nil)
        let msg2 = OpenAIAssistantMessage(content: "Tool failed.", toolCalls: nil, audio: nil)

        await controller.mockChatResponse([msg1])
        await controller.mockChatResponse([msg2])

        // 3. Run Agent
        let stream = await agentClient.process(
            messages: [.openai(.user(.init(content: "Run throwing tool")))],
            model: "gpt-4",
            tools: [throwingTool],
            source: source
        )

        var toolErrorFound = false
        for try await part in stream {
            if case .message(let msg) = part,
                case .openai(let openAIMsg) = msg,
                case .tool(let toolMsg) = openAIMsg
            {
                if toolMsg.toolCallId == "call_error" {
                    if toolMsg.content.contains("Error: Something went wrong") {
                        toolErrorFound = true
                    }
                }
            }
        }
        XCTAssertTrue(toolErrorFound)
    }

    func testCancellation() async throws {
        // 1. Setup long running task
        let client = self.agentClient!
        let src = self.source!

        let task = Task {
            let stream = await client.process(
                messages: [],
                model: "gpt-4",
                tools: [],
                source: src
            )
            for try await _ in stream {}
        }

        // 2. Cancel immediately
        task.cancel()

        // 3. Expect completion without error or with cancellation error
        let _ = await task.result
    }

    func testInvalidURL() async throws {
        let badSource = Source(
            displayName: "Bad", endpoint: "invalid-url", apiKey: "key", apiType: .openAI)

        let stream = await agentClient.process(
            messages: [],
            model: "gpt-4",
            tools: [],
            source: badSource
        )

        do {
            for try await _ in stream {}
            XCTFail("Should throw error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
