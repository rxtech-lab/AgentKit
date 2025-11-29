import Testing
import Vapor

@testable import Agent

@Suite("AgentClient Tests", .serialized)
struct AgentClientTests {
    struct TestContext {
        let app: Application
        let controller: OpenAIChatController
        let source: Source
        let agentClient: AgentClient
    }

    /// Helper that creates a Vapor app, runs the test body, and ensures cleanup
    static func withApp(
        _ body: (TestContext) async throws -> Void
    ) async throws {
        // Use custom environment to avoid parsing command-line args from Swift Testing
        let app = try await Application.make(.custom(name: "testing"))
        let controller = await OpenAIChatController()
        await controller.registerRoutes(on: app)
        let port = 8124

        // Use server.start instead of startup to avoid command parsing
        try await app.server.start(address: .hostname("localhost", port: port))

        let source = Source.openAI(
            client: OpenAIClient(apiKey: "test", baseURL: URL(string: "http://localhost:\(port)")!),
            models: []
        )
        let agentClient = AgentClient()
        let context = TestContext(app: app, controller: controller, source: source, agentClient: agentClient)

        do {
            try await body(context)
            await app.server.shutdown()
            try await app.asyncShutdown()
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }

    @Test func testMultiTurnConversationWithTools() async throws {
        try await Self.withApp { ctx in
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

            let msg1Part1 = OpenAIAssistantMessage(
                content: nil, toolCalls: [delta1], audio: nil, reasoning: nil)
            let msg1Part2 = OpenAIAssistantMessage(
                content: nil, toolCalls: [delta2], audio: nil, reasoning: nil)

            // Turn 2: Final Answer
            let msg2 = OpenAIAssistantMessage(
                content: "It is sunny in Paris.", toolCalls: nil, audio: nil, reasoning: nil)

            await ctx.controller.mockChatResponse([msg1Part1, msg1Part2])
            await ctx.controller.mockChatResponse([msg2])

            // 3. Run Agent
            let stream = await ctx.agentClient.process(
                messages: [.openai(.user(.init(content: "Weather in Paris?")))],
                model: .custom(CustomModel(id: "gpt-4")),
                source: ctx.source,
                tools: [weatherTool]
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
            #expect(receivedContent.contains("It is sunny in Paris."))
            // messageCount should include:
            // 1. Assistant message (tool call)
            // 2. Tool message (result)
            // 3. Assistant message (final answer)
            #expect(messageCount >= 3)
        }
    }

    @Test func testToolCallWithInvalidArguments() async throws {
        try await Self.withApp { ctx in
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

            let msg1 = OpenAIAssistantMessage(
                content: nil, toolCalls: [invalidToolCall], audio: nil, reasoning: nil)
            let msg2 = OpenAIAssistantMessage(
                content: "I need the location.", toolCalls: nil, audio: nil, reasoning: nil)

            await ctx.controller.mockChatResponse([msg1])
            await ctx.controller.mockChatResponse([msg2])

            // 3. Run Agent
            let stream = await ctx.agentClient.process(
                messages: [.openai(.user(.init(content: "Weather in Paris?")))],
                model: .custom(CustomModel(id: "gpt-4")),
                source: ctx.source,
                tools: [weatherTool]
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

            #expect(toolErrorMessageFound, "Should have received a tool message with error")
        }
    }

    @Test func testToolCallWithEncodingError() async throws {
        // This test doesn't need the app - it's documenting unreachable code
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

    @Test func testToolNotFound() async throws {
        try await Self.withApp { ctx in
            // 1. Setup Tools (Empty)
            let tools: [AgentTool<String, String>] = []

            // 2. Setup Mock
            let toolCall = OpenAIToolCall(
                index: 0, id: "call_missing", type: .function,
                function: .init(name: "missing_tool", arguments: "{}")
            )

            let msg1 = OpenAIAssistantMessage(
                content: nil, toolCalls: [toolCall], audio: nil, reasoning: nil)
            let msg2 = OpenAIAssistantMessage(
                content: "Tool not found.", toolCalls: nil, audio: nil, reasoning: nil)

            await ctx.controller.mockChatResponse([msg1])
            await ctx.controller.mockChatResponse([msg2])

            // 3. Run Agent
            let stream = await ctx.agentClient.process(
                messages: [.openai(.user(.init(content: "Run missing tool")))],
                model: .custom(CustomModel(id: "gpt-4")),
                source: ctx.source,
                tools: tools
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
            #expect(toolErrorFound)
        }
    }

    @Test func testGenericToolExecutionError() async throws {
        try await Self.withApp { ctx in
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

            let msg1 = OpenAIAssistantMessage(
                content: nil, toolCalls: [toolCall], audio: nil, reasoning: nil)
            let msg2 = OpenAIAssistantMessage(
                content: "Tool failed.", toolCalls: nil, audio: nil, reasoning: nil)

            await ctx.controller.mockChatResponse([msg1])
            await ctx.controller.mockChatResponse([msg2])

            // 3. Run Agent
            let stream = await ctx.agentClient.process(
                messages: [.openai(.user(.init(content: "Run throwing tool")))],
                model: .custom(CustomModel(id: "gpt-4")),
                source: ctx.source,
                tools: [throwingTool]
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
            #expect(toolErrorFound, "Expected to find tool error message")
        }
    }

    @Test func testCancellation() async throws {
        try await Self.withApp { ctx in
            // 1. Setup long running task
            let client = ctx.agentClient
            let src = ctx.source

            let task = Task {
                let stream = await client.process(
                    messages: [],
                    model: .custom(CustomModel(id: "gpt-4")),
                    source: src,
                    tools: []
                )
                for try await _ in stream {}
            }

            // 2. Cancel immediately
            task.cancel()

            // 3. Expect completion without error or with cancellation error
            let _ = await task.result
        }
    }

    @Test func testInvalidSourceForModel() async throws {
        // This test doesn't need the full app - just tests error handling
        let openAISource = Source.openAI(
            client: OpenAIClient(apiKey: "test"),
            models: []
        )

        let agentClient = AgentClient()
        let stream = await agentClient.process(
            messages: [],
            model: .openRouter(OpenAICompatibleModel(id: "test-model")),
            source: openAISource,
            tools: []
        )

        do {
            for try await _ in stream {}
            Issue.record("Should throw error")
        } catch {
            #expect(error is AgentClientError)
        }
    }
}
