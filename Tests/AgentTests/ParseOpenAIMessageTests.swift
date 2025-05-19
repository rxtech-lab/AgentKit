import XCTest

@testable import Agent

class ParseOpenAIMessageTests: XCTestCase {
    func testParseOpenAIAssistantMessage() {
        let data = """
        {
            "role": "assistant",
            "refusal": "string",
            "content": "string",
            "tool_calls": [
                {
                "id": "string",
                "type": "function",
                "function": {
                    "name": "string",
                    "arguments": "string"
                }
                }
            ],
            "function_call": {
                "name": "string",
                "arguments": "string"
            },
            "audio": {
                "id": "string",
                "expires_at": 0,
                "data": "string",
                "transcript": "string"
            },
        }
        """

        let message = try! JSONDecoder().decode(OpenAIMessage.self, from: data.data(using: .utf8)!)
        if case .assistant(let assistantMessage) = message {
            XCTAssertEqual(assistantMessage.content, "string")
            XCTAssertEqual(assistantMessage.toolCalls?.count, 1)
            XCTAssertEqual(assistantMessage.toolCalls?[0].id, "string")
            XCTAssertEqual(assistantMessage.toolCalls?[0].type, .function)
            XCTAssertEqual(assistantMessage.toolCalls?[0].function.name, "string")
            XCTAssertEqual(assistantMessage.toolCalls?[0].function.arguments, "string")
        } else {
            XCTFail("Message is not an assistant message")
        }
    }

    func testParseOpenAISystemMessage() {
        let data = """
        {
            "role": "system",
            "content": "string"
        }
        """

        let message = try! JSONDecoder().decode(OpenAIMessage.self, from: data.data(using: .utf8)!)
        if case .system(let systemMessage) = message {
            XCTAssertEqual(systemMessage.content, "string")
        } else {
            XCTFail("Message is not a system message")
        }
    }

    func testSerializeMessages() {
        let userMessage = OpenAIUserMessage(content: "Hello")
        let assistantMessage = OpenAIAssistantMessage(content: "Hi there!", audio: nil)
        let systemMessage = OpenAISystemMessage(content: "System message")

        let messages: [OpenAIMessage] = [
            .user(userMessage),
            .assistant(assistantMessage),
            .system(systemMessage)
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(messages)
        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertNotNil(jsonString)
    }
}
