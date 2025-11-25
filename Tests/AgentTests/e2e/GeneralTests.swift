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

    @Test
    func testRealOpenAIToolCall() async throws {
        // 1. Load configuration
        let (client, source, model) = try await setUpTests()

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
            model: model,
            source: source,
            tools: [addTool]
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
        let (client, source, model) = try await setUpTests()
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
            model: model,
            source: source,
            tools: [weatherTool]
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
            model: model,
            source: source,
            tools: [weatherTool]
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
        let (client, source, model) = try await setUpTests()
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
            model: model,
            source: source,
            tools: [failingTool]
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
        let (client, source, model) = try await setUpTests()
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
            model: model,
            source: source,
            tools: [uiTool]
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
    /**
     Agent should be able to call multiple tools and respond until the finish_reason is stop.
     */
    func testMultipleToolCallsWithAssistantMessage() async throws {

        struct Tool1Input: Decodable {
            let a: Int
        }

        struct Tool2Input: Decodable {
            let b: Int
        }

        actor ToolCallTracker {
            var tool1Called = false
            var tool2Called = false

            func tool1Called() async {
                tool1Called = true
            }

            func tool2Called() async {
                tool2Called = true
            }
        }

        let (client, source, model) = try await setUpTests()

        let toolCallTracker = ToolCallTracker()

        let tool1 = AgentTool(
            name: "tool1",
            description: "Tool 1",
            parameters: .object(properties: ["a": .integer()], required: ["a"])
        ) { (args: Tool1Input) async in
            await toolCallTracker.tool1Called()
            return args.a + 1
        }

        let tool2 = AgentTool(
            name: "tool2",
            description: "Tool 2",
            parameters: .object(properties: ["b": .integer()], required: ["b"])
        ) { (args: Tool2Input) in
            await toolCallTracker.tool2Called()
            return args.b + 2
        }

        let messages: [Message] = [
            .openai(
                .system(
                    .init(
                        content:
                            "Call the tool1 then tool2 in sequence. Return the result of the second tool."
                    ))),
            .openai(.user(.init(content: "Use tool 1 with input 5"))),
        ]

        let stream = await client.process(
            messages: messages,
            model: model,
            source: source,
            tools: [tool1, tool2]
        )

        var generatedMessages: [OpenAIMessage] = []
        for try await part in stream {
            if case .message(let msg) = part, case .openai(let openAIMsg) = msg {
                generatedMessages.append(openAIMsg)
            }
        }
        #expect(await toolCallTracker.tool1Called, "The tool1 tool should have been called")
        #expect(await toolCallTracker.tool2Called, "The tool2 tool should have been called")

        // Check we have assistant messages with tool calls
        let assistantMessagesWithToolCalls = generatedMessages.filter { msg in
            if case .assistant(let assistantMsg) = msg, let toolCalls = assistantMsg.toolCalls, !toolCalls.isEmpty {
                return true
            }
            return false
        }
        #expect(assistantMessagesWithToolCalls.count >= 2, "Should have at least 2 assistant messages with tool calls")

        // Check we have tool result messages
        let toolMessages: [OpenAIToolMessage] = generatedMessages.filter { $0.role == .tool }
            .map { if case .tool(let toolMsg) = $0 { return toolMsg } else { return nil } }
            .compactMap { $0 }
        #expect(toolMessages.count >= 2, "Should have at least 2 tool result messages")

        let lastMessage = generatedMessages.last
        // make sure the last message is an assistant message
        #expect(lastMessage?.role == .assistant, "Last message should be an assistant message")
    }

    @Test
    /**
    Agent will stop responding if tool is UI tool.
    */
    func testUIStop() async throws {
        struct UIInput: Decodable {
            let message: String
        }

        let (client, source, model) = try await setUpTests()

        let uiTool = AgentTool(
            name: "ui_tool",
            description: "UI tool",
            parameters: .object(properties: ["message": .string()], required: ["message"]),
            toolType: .ui
        ) { (args: UIInput) in
            return "User confirmed: \(args.message)"
        }

        let messages: [Message] = [
            .openai(.user(.init(content: "Ask for confirmation saying 'Proceed?'")))
        ]

        let stream = await client.process(
            messages: messages,
            model: model,
            source: source,
            tools: [uiTool]
        )

        var generatedMessages: [OpenAIMessage] = []
        for try await part in stream {
            if case .message(let msg) = part, case .openai(let openAIMsg) = msg {
                generatedMessages.append(openAIMsg)
            }
        }

        // Check we have 1 assistant message with tool call (UI tool)
        let assistantMessagesWithToolCalls = generatedMessages.filter { msg in
            if case .assistant(let assistantMsg) = msg, let toolCalls = assistantMsg.toolCalls, !toolCalls.isEmpty {
                return true
            }
            return false
        }
        #expect(assistantMessagesWithToolCalls.count == 1, "Should have 1 assistant message with tool call")

        let lastMessage = generatedMessages.last
        // last message should be assistant message (UI tool stops before execution)
        #expect(lastMessage?.role == .assistant, "Last message should be an assistant message")
    }
}
