import Foundation
import Testing

@testable import Agent

struct TestError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

struct IntegrationTests {

    func setUpTests() async throws -> (AgentClient, Source, String) {
        let env = loadEnv()
        let apiKey = env["OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let endpoint = env["OPENAI_API_BASE_URL"]
        let modelName = env["OPENAI_MODEL"]

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            // fail the test
            #expect(Bool(false), "OPENAI_API_KEY not found in .env or environment")
            throw TestError("OPENAI_API_KEY not found in .env or environment")
        }
        guard let endpoint = endpoint, !endpoint.isEmpty else {
            // fail the test
            #expect(Bool(false), "OPENAI_API_BASE_URL not found in .env or environment")
            throw TestError("OPENAI_API_BASE_URL not found in .env or environment")
        }
        guard let modelName = modelName, !modelName.isEmpty else {
            // fail the test
            #expect(Bool(false), "OPENAI_MODEL not found in .env or environment")
            throw TestError("OPENAI_MODEL not found in .env or environment")
        }
        let source = Source(
            displayName: "OpenAI", endpoint: endpoint, apiKey: apiKey, apiType: .openAI)
        let client = AgentClient()
        return (client, source, modelName)
    }

    // Helper to load .env file
    private func loadEnv() -> [String: String] {
        let fileManager = FileManager.default
        // Try to find .env in the project root
        // Start from the current file path and go up
        var currentURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        // Go up until we find .env or hit root
        while currentURL.pathComponents.count > 1 {
            let envURL = currentURL.appendingPathComponent(".env")
            if fileManager.fileExists(atPath: envURL.path) {
                do {
                    let contents = try String(contentsOf: envURL, encoding: .utf8)
                    var env: [String: String] = [:]
                    contents.enumerateLines { line, _ in
                        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            // Remove quotes if present
                            let cleanValue = value.trimmingCharacters(
                                in: CharacterSet(charactersIn: "\"'"))
                            env[key] = cleanValue
                        }
                    }
                    return env
                } catch {
                    print("Error reading .env: \(error)")
                }
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        return [:]
    }

    @Test
    func testRealOpenAIToolCall() async throws {
        // 1. Load configuration
        let (client, source, modelName) = try await setUpTests()

        // 3. Define a simple tool
        struct CalculatorInput: Decodable {
            let a: Int
            let b: Int
        }

        let addTool = AgentTool(
            name: "add_numbers",
            description: "Add two numbers together",
            parameters: .object(
                properties: [
                    "a": .integer(description: "First number"),
                    "b": .integer(description: "Second number"),
                ],
                required: ["a", "b"]
            )
        ) { (args: CalculatorInput) in
            return args.a + args.b
        }

        // 4. Run the agent
        // We ask it to add 5 and 7. Expect tool call and final answer 12.
        let messages: [Message] = [
            .openai(.user(.init(content: "What is 5 + 7? Use the add_numbers tool.")))
        ]

        let stream = await client.process(
            messages: messages,
            model: modelName,
            tools: [addTool],
            source: source
        )

        var toolCalled = false
        var finalContent = ""

        for try await part in stream {
            switch part {
            case .message(let msg):
                if case .openai(let openAIMsg) = msg {
                    // Check for tool call in assistant message
                    if case .assistant(let assistantMsg) = openAIMsg,
                        let toolCalls = assistantMsg.toolCalls,
                        !toolCalls.isEmpty
                    {
                        // We see the assistant trying to call the tool
                        if toolCalls.contains(where: { $0.function?.name == "add_numbers" }) {
                            // Good, it decided to call it.
                        }
                    }

                    // Check for tool execution result (which comes as a tool message from the client)
                    if case .tool(let toolMsg) = openAIMsg {
                        print("Tool result: \(toolMsg.content)")
                        if toolMsg.content == "12" {
                            toolCalled = true
                        }
                    }

                    // Check final answer
                    if case .assistant(let assistantMsg) = openAIMsg,
                        let content = assistantMsg.content
                    {
                        finalContent = content
                    }
                }
            case .textDelta(let text):
                finalContent += text
            case .error(let error):
                throw error
            }
        }

        // 5. Assertions
        #expect(toolCalled, "The add_numbers tool should have been called and returned 12")
        #expect(finalContent.contains("12"), "The final response should contain the result 12")
    }

    @Test
    func testMultiTurnConversation() async throws {
        // 1. Load configuration
        let (client, source, modelName) = try await setUpTests()
        // 3. Define a tool
        struct WeatherInput: Decodable {
            let location: String
        }

        let weatherTool = AgentTool(
            name: "get_weather",
            description: "Get weather for a location",
            parameters: .object(
                properties: ["location": .string(description: "City name")],
                required: ["location"]
            )
        ) { (args: WeatherInput) in
            return "Sunny in \(args.location)"
        }

        // 4. Run conversation
        // Turn 1: User asks for weather
        let messages1: [Message] = [
            .openai(.user(.init(content: "What is the weather in Paris?")))
        ]

        var conversation: [Message] = messages1
        var toolCalled = false
        var assistantResponse1 = ""

        let stream1 = await client.process(
            messages: conversation,
            model: modelName,
            tools: [weatherTool],
            source: source
        )

        for try await part in stream1 {
            if case .message(let msg) = part {
                conversation.append(msg)  // Accumulate history
                if case .openai(let openAIMsg) = msg {
                    if case .tool = openAIMsg {
                        toolCalled = true
                    }
                    if case .assistant(let am) = openAIMsg, let content = am.content {
                        assistantResponse1 = content
                    }
                }
            }
        }

        #expect(toolCalled, "Weather tool should be called")
        #expect(
            assistantResponse1.localizedCaseInsensitiveContains("Sunny"),
            "Response should mention Sunny")

        // Turn 2: User asks follow-up
        conversation.append(.openai(.user(.init(content: "What about London?"))))

        var assistantResponse2 = ""
        var toolCalled2 = false

        let stream2 = await client.process(
            messages: conversation,
            model: modelName,
            tools: [weatherTool],
            source: source
        )

        for try await part in stream2 {
            if case .message(let msg) = part {
                if case .openai(let openAIMsg) = msg {
                    if case .tool = openAIMsg {
                        toolCalled2 = true
                    }
                    if case .assistant(let am) = openAIMsg, let content = am.content {
                        assistantResponse2 = content
                    }
                }
            }
        }

        #expect(toolCalled2, "Weather tool should be called again for London")
        #expect(
            assistantResponse2.localizedCaseInsensitiveContains("Sunny"),
            "Response should mention Sunny for London")
    }

    @Test
    func testToolFailureHandling() async throws {
        // 1. Load configuration
        let (client, source, modelName) = try await setUpTests()
        // 3. Define a failing tool
        struct FailInput: Decodable {
            let reason: String
        }

        let failingTool = AgentTool(
            name: "failing_tool",
            description: "Always fails with an error",
            parameters: .object(
                properties: ["reason": .string()],
                required: ["reason"]
            )
        ) { (args: FailInput) -> String in
            throw NSError(
                domain: "Test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Tool execution failed: \(args.reason)"])
        }

        // 4. Run agent
        let messages: [Message] = [
            .openai(
                .user(.init(content: "Please run the failing_tool with reason 'test_failure'.")))
        ]

        let stream = await client.process(
            messages: messages,
            model: modelName,
            tools: [failingTool],
            source: source
        )

        var errorReportedInToolMessage = false
        var finalResponse = ""

        var lastMessage: AgentResponsePart?
        for try await part in stream {
            if case .message(let msg) = part, case .openai(let openAIMsg) = msg {
                lastMessage = part
                if case .tool(let tm) = openAIMsg {
                    print("Tool output: \(tm.content)")
                    if tm.content.contains("Error:")
                        && tm.content.contains("Tool execution failed: test_failure")
                    {
                        errorReportedInToolMessage = true
                    }
                }
                if case .assistant(let am) = openAIMsg, let content = am.content {
                    finalResponse = content
                }
            }
        }

        // check last message is a assistant message
        if let last = lastMessage, case .message(let msg) = last,
            case .openai(let openAIMsg) = msg
        {
            if case .assistant = openAIMsg {
                // This is expected
            } else {
                #expect(Bool(false), "Last message should be an assistant message")
            }
        } else {
            #expect(Bool(false), "Should have received at least one message")
        }

        #expect(errorReportedInToolMessage, "The tool message should contain the error description")
        // The model usually apologizes or explains the error after receiving the tool error message
        #expect(!finalResponse.isEmpty, "Model should provide a final response after tool failure")
    }

    @Test
    func testUIToolHandling() async throws {
        // 1. Load configuration
        let (client, source, modelName) = try await setUpTests()
        // 3. Define a UI Tool
        struct ConfirmInput: Decodable {
            let message: String
        }

        let uiTool = AgentTool(
            name: "show_confirmation",
            description: "Ask user for confirmation",
            parameters: .object(
                properties: ["message": .string()],
                required: ["message"]
            ),
            toolType: .ui  // Important: This pauses execution
        ) { (args: ConfirmInput) in
            return "User confirmed: \(args.message)"
        }

        // 4. Run agent
        let messages: [Message] = [
            .openai(.user(.init(content: "Ask for confirmation saying 'Proceed?'")))
        ]

        let stream = await client.process(
            messages: messages,
            model: modelName,
            tools: [uiTool],
            source: source
        )

        var toolCallDetected = false
        var streamEndedWithoutToolResult = true

        for try await part in stream {
            if case .message(let msg) = part, case .openai(let openAIMsg) = msg {
                if case .assistant(let am) = openAIMsg, let toolCalls = am.toolCalls {
                    if toolCalls.contains(where: { $0.function?.name == "show_confirmation" }) {
                        toolCallDetected = true
                    }
                }
                // If we see a tool message, that means the client automatically executed it.
                // For a UI tool, we expect the stream to END (finish) WITHOUT automatically producing a tool message.
                if case .tool = openAIMsg {
                    streamEndedWithoutToolResult = false
                }
            }
        }

        #expect(toolCallDetected, "The UI tool should have been requested by the model")
        #expect(
            streamEndedWithoutToolResult,
            "The stream should finish without executing the UI tool automatically")
    }

    @Test
    func testGeminiModelWithReasoning() async throws {
        // 1. Load configuration
        let (client, source, _) = try await setUpTests()
        // 3. Define a tool

        // 4. Run agent
        let messages: [Message] = [
            .openai(.user(.init(content: "Please reason about the user's request.")))
        ]

        let stream = await client.process(
            messages: messages,
            model: "google/gemini-3-pro-preview",
            tools: [],
            source: source
        )

        var finalContent = ""

        for try await part in stream {
            if case .message(let msg) = part, case .openai(let openAIMsg) = msg {
                if case .assistant(let am) = openAIMsg, let content = am.content {
                    finalContent += content
                }
            }
        }
        #expect(
            finalContent.count > 0)
    }
}
