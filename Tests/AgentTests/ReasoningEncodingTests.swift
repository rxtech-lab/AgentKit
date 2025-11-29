//
//  ReasoningEncodingTests.swift
//  AgentTests
//
//  Created by Claude on 11/29/25.
//

import Foundation
import Testing

@testable import Agent

struct ReasoningEncodingTests {

    // MARK: - OpenAIAssistantMessage Encoding/Decoding

    @Test
    func testAssistantMessageWithReasoningEncodeDecode() throws {
        let original = OpenAIAssistantMessage(
            id: "test-id",
            content: "This is the response",
            toolCalls: nil,
            audio: nil,
            reasoning: "Let me think step by step...",
            reasoningDetails: [
                .init(
                    type: .summary, id: "summary-1", format: "anthropic-claude-v1", index: 0,
                    summary: "The model analyzed the problem...")
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify reasoning is in the encoded JSON
        #expect(jsonString.contains("reasoning"))
        #expect(jsonString.contains("Let me think step by step..."))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIAssistantMessage.self, from: data)

        #expect(decoded.content == original.content)
        #expect(decoded.reasoning == original.reasoning)
        #expect(decoded.reasoning == "Let me think step by step...")
        #expect(decoded.reasoningDetails?.count == 1)
        #expect(decoded.reasoningDetails?.first?.summary == "The model analyzed the problem...")
    }

    @Test
    func testAssistantMessageWithReasoningDetailsEncodeDecode() throws {
        let reasoningDetails = [
            OpenAIAssistantMessage.ReasoningDetail(
                type: .summary,
                id: "summary-1",
                format: "anthropic-claude-v1",
                index: 0,
                summary: "The model analyzed the problem..."
            ),
            OpenAIAssistantMessage.ReasoningDetail(
                type: .text,
                id: "text-1",
                format: "anthropic-claude-v1",
                index: 1,
                text: "Step 1: First I need to...\nStep 2: Then I will...",
                signature: "sha256:abc123"
            ),
        ]

        let original = OpenAIAssistantMessage(
            id: "test-id",
            content: "Here is my response",
            toolCalls: nil,
            audio: nil,
            reasoning: "Full reasoning text here",
            reasoningDetails: reasoningDetails
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify reasoning_details is in the encoded JSON
        #expect(jsonString.contains("reasoning_details"))
        #expect(jsonString.contains("reasoning.summary"))
        #expect(jsonString.contains("reasoning.text"))
        #expect(jsonString.contains("The model analyzed the problem..."))
        #expect(jsonString.contains("Step 1: First I need to..."))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIAssistantMessage.self, from: data)

        #expect(decoded.content == original.content)
        #expect(decoded.reasoning == original.reasoning)
        #expect(decoded.reasoningDetails?.count == 2)

        let decodedSummary = decoded.reasoningDetails?.first(where: { $0.type == .summary })
        #expect(decodedSummary?.summary == "The model analyzed the problem...")

        let decodedText = decoded.reasoningDetails?.first(where: { $0.type == .text })
        #expect(decodedText?.text == "Step 1: First I need to...\nStep 2: Then I will...")
        #expect(decodedText?.signature == "sha256:abc123")
    }

    @Test
    func testAssistantMessageWithoutReasoningEncodeDecode() throws {
        let original = OpenAIAssistantMessage(
            id: "test-id",
            content: "Simple response",
            toolCalls: nil,
            audio: nil,
            reasoning: nil,
            reasoningDetails: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        // Verify reasoning key is NOT in the encoded JSON when nil
        // (encodeIfPresent should skip nil values)
        #expect(!jsonString.contains("\"reasoning\""))
        #expect(!jsonString.contains("reasoning_details"))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIAssistantMessage.self, from: data)

        #expect(decoded.content == original.content)
        #expect(decoded.reasoning == nil)
        #expect(decoded.reasoningDetails == nil)
    }

    // MARK: - OpenAIMessage (enum) Encoding/Decoding

    @Test
    func testOpenAIMessageEnumWithReasoningEncodeDecode() throws {
        let assistantMessage = OpenAIAssistantMessage(
            id: "test-id",
            content: "Response with reasoning",
            toolCalls: nil,
            audio: nil,
            reasoning: "My reasoning process...",
            reasoningDetails: [
                .init(type: .summary, id: "s1", summary: "Summary here")
            ]
        )

        let original = OpenAIMessage.assistant(assistantMessage)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIMessage.self, from: data)

        if case .assistant(let decodedAssistant) = decoded {
            #expect(decodedAssistant.content == "Response with reasoning")
            #expect(decodedAssistant.reasoning == "My reasoning process...")
            #expect(decodedAssistant.reasoningDetails?.count == 1)
            #expect(decodedAssistant.reasoningDetails?.first?.summary == "Summary here")
        } else {
            Issue.record("Expected assistant message")
        }
    }

    // MARK: - ReasoningDetail Encoding/Decoding

    @Test
    func testReasoningDetailSummaryEncodeDecode() throws {
        let original = OpenAIAssistantMessage.ReasoningDetail(
            type: .summary,
            id: "summary-id",
            format: "format-v1",
            index: 0,
            summary: "This is the summary"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("reasoning.summary"))
        #expect(jsonString.contains("This is the summary"))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIAssistantMessage.ReasoningDetail.self, from: data)

        #expect(decoded.type == .summary)
        #expect(decoded.id == "summary-id")
        #expect(decoded.summary == "This is the summary")
        #expect(decoded.text == nil)
    }

    @Test
    func testReasoningDetailTextEncodeDecode() throws {
        let original = OpenAIAssistantMessage.ReasoningDetail(
            type: .text,
            id: "text-id",
            format: "format-v1",
            index: 1,
            text: "Detailed reasoning text here",
            signature: "sig123"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("reasoning.text"))
        #expect(jsonString.contains("Detailed reasoning text here"))
        #expect(jsonString.contains("sig123"))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OpenAIAssistantMessage.ReasoningDetail.self, from: data)

        #expect(decoded.type == .text)
        #expect(decoded.id == "text-id")
        #expect(decoded.text == "Detailed reasoning text here")
        #expect(decoded.signature == "sig123")
        #expect(decoded.summary == nil)
    }

    // MARK: - JSON String Round-trip

    @Test
    func testJSONStringRoundTrip() throws {
        // Simulate what would come from an API or database
        let jsonString = """
            {
                "role": "assistant",
                "content": "Here is my answer",
                "reasoning": "I thought about this carefully",
                "reasoning_details": [
                    {
                        "type": "reasoning.summary",
                        "id": "s1",
                        "summary": "Analyzed the problem"
                    },
                    {
                        "type": "reasoning.text",
                        "id": "t1",
                        "text": "Step by step reasoning...",
                        "signature": "abc"
                    }
                ]
            }
            """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let message = try decoder.decode(OpenAIAssistantMessage.self, from: data)

        #expect(message.content == "Here is my answer")
        #expect(message.reasoning == "I thought about this carefully")
        #expect(message.reasoningDetails?.count == 2)

        // Re-encode and verify
        let encoder = JSONEncoder()
        let reEncodedData = try encoder.encode(message)
        let reDecoded = try decoder.decode(OpenAIAssistantMessage.self, from: reEncodedData)

        #expect(reDecoded.content == message.content)
        #expect(reDecoded.reasoning == message.reasoning)
        #expect(reDecoded.reasoningDetails?.count == message.reasoningDetails?.count)
    }
}
