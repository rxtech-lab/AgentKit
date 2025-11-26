import Foundation
import Testing

@testable import Agent

struct OpenAIOpenRouterTests {

    @Test
    /**
     Agent should be able to call multiple tools and respond until the finish_reason is stop.
     Uses OpenAI model via OpenRouter.
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

            func markTool1Called() async {
                tool1Called = true
            }

            func markTool2Called() async {
                tool2Called = true
            }
        }

        let (client, source, _) = try await setUpTests()
        let model = Model.custom(CustomModel(id: "openai/gpt-5.1-codex-mini"))

        let toolCallTracker = ToolCallTracker()

        let tool1 = AgentTool(
            name: "tool1",
            description: "Tool 1",
            parameters: .object(properties: ["a": .integer()], required: ["a"])
        ) { (args: Tool1Input) async in
            await toolCallTracker.markTool1Called()
            return args.a + 1
        }

        let tool2 = AgentTool(
            name: "tool2",
            description: "Tool 2",
            parameters: .object(properties: ["b": .integer()], required: ["b"])
        ) { (args: Tool2Input) in
            await toolCallTracker.markTool2Called()
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
            if case .assistant(let assistantMsg) = msg, let toolCalls = assistantMsg.toolCalls,
                !toolCalls.isEmpty
            {
                return true
            }
            return false
        }
        #expect(
            assistantMessagesWithToolCalls.count >= 2,
            "Should have at least 2 assistant messages with tool calls")

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
     Test that multi-turn conversation with tool calls works correctly.
     This test reproduces the scenario where:
     1. User sends message
     2. Assistant responds with tool call
     3. Tool result is sent back
     4. Assistant responds
     5. User sends another message - this previously failed with "Expected an ID that begins with 'msg'" error

     The fix: Message IDs are no longer included when encoding messages for the OpenAI API.
     */
    func testMultiTurnConversationAfterToolCallDoesNotFailWithInvalidId() async throws {
        struct GreetInput: Decodable {
            let name: String
        }

        let (client, source, _) = try await setUpTests()
        let model = Model.custom(CustomModel(id: "openai/gpt-4.1-mini"))

        let greetTool = AgentTool(
            name: "greet",
            description: "Greet someone by name",
            parameters: .object(properties: ["name": .string()], required: ["name"])
        ) { (args: GreetInput) async in
            return "Hello, \(args.name)!"
        }

        // First turn: user message triggers tool call
        let messages1: [Message] = [
            .openai(.system(.init(content: "You are a greeting assistant. Use the greet tool when asked to greet someone."))),
            .openai(.user(.init(content: "Please greet Alice"))),
        ]

        let stream1 = await client.process(
            messages: messages1,
            model: model,
            source: source,
            tools: [greetTool]
        )

        var allMessages: [Message] = messages1
        for try await part in stream1 {
            if case .message(let msg) = part {
                allMessages.append(msg)
            }
        }

        // Verify we got an assistant response with content
        let lastAssistantMessage = allMessages.last { msg in
            if case .openai(let openAIMsg) = msg, case .assistant = openAIMsg {
                return true
            }
            return false
        }
        #expect(lastAssistantMessage != nil, "Should have an assistant response")

        // Second turn: send another user message using the same conversation history
        // This is where the bug occurred - OpenAI rejected the message ID format
        let secondUserMessage = Message.openai(.user(.init(content: "Now greet Bob")))
        allMessages.append(secondUserMessage)

        let stream2 = await client.process(
            messages: allMessages,
            model: model,
            source: source,
            tools: [greetTool]
        )

        var secondTurnMessages: [Message] = []
        for try await part in stream2 {
            if case .message(let msg) = part {
                secondTurnMessages.append(msg)
            }
        }

        // Verify the second turn completed successfully
        #expect(!secondTurnMessages.isEmpty, "Second turn should produce messages")

        // The last message should be an assistant message
        if let lastMsg = secondTurnMessages.last, case .openai(let openAIMsg) = lastMsg {
            #expect(openAIMsg.role == .assistant, "Last message should be an assistant message")
        } else {
            Issue.record("Expected assistant message in second turn")
        }
    }
}
