import Foundation
import Testing

@testable import Agent

struct ReasoningTests {

    @Test
    /**
     Test that reasoning/thinking content is captured from models that support it.
     Uses OpenRouter with openai/gpt-5.1-codex-mini model and a Solidity prompt.
     */
    func testReasoningWithSolidityPrompt() async throws {
        let (client, source, _) = try await setUpTests()

        // Use model that supports reasoning
        let model = Model.custom(
            CustomModel(
                id: "openai/gpt-5.1-codex-mini",
                reasoningConfig: ReasoningConfig.default
            )
        )

        let messages: [Message] = [
            .openai(
                .user(
                    .init(
                        content:
                            "Think about writing a Solidity program that implements a simple ERC20 token"
                    )))
        ]

        let stream = await client.process(
            messages: messages,
            model: model,
            source: source,
            tools: []
        )

        var assistantMessages: [OpenAIAssistantMessage] = []
        for try await part in stream {
            if case .message(let msg) = part,
                case .openai(let openAIMsg) = msg,
                case .assistant(let assistantMsg) = openAIMsg
            {
                assistantMessages.append(assistantMsg)
            }
        }

        // Verify we got a response
        #expect(!assistantMessages.isEmpty, "Should have assistant response")

        // Check for reasoning content
        let lastMessage = assistantMessages.last!
        let hasReasoning = (lastMessage.reasoning != nil && !lastMessage.reasoning!.isEmpty)
            || (lastMessage.reasoningDetails != nil && !lastMessage.reasoningDetails!.isEmpty)

        #expect(hasReasoning, "Model should return reasoning content")

        // If reasoningDetails exists, verify structure
        if let details = lastMessage.reasoningDetails {
            let summaries = details.filter { $0.type == .summary }
            let texts = details.filter { $0.type == .text }

            // Log what we received for debugging
            print("Received \(summaries.count) summary items and \(texts.count) text items")

            if !summaries.isEmpty {
                #expect(
                    summaries.first?.summary != nil, "Summary type should have summary field")
            }
            if !texts.isEmpty {
                #expect(texts.first?.text != nil, "Text type should have text field")
            }
        }
    }

    @Test
    /**
     Test that messages without reasoning still work correctly.
     Uses a simple prompt that shouldn't trigger extensive reasoning.
     */
    func testSimplePromptWithoutReasoning() async throws {
        let (client, source, _) = try await setUpTests()

        // Use model without reasoning config
        let model = Model.custom(
            CustomModel(id: "openai/gpt-4.1-mini")
        )

        let messages: [Message] = [
            .openai(.user(.init(content: "Say hello")))
        ]

        let stream = await client.process(
            messages: messages,
            model: model,
            source: source,
            tools: []
        )

        var assistantMessages: [OpenAIAssistantMessage] = []
        for try await part in stream {
            if case .message(let msg) = part,
                case .openai(let openAIMsg) = msg,
                case .assistant(let assistantMsg) = openAIMsg
            {
                assistantMessages.append(assistantMsg)
            }
        }

        // Verify we got a response
        #expect(!assistantMessages.isEmpty, "Should have assistant response")

        // Verify content exists
        let lastMessage = assistantMessages.last!
        #expect(lastMessage.content != nil, "Should have content")
    }
}
