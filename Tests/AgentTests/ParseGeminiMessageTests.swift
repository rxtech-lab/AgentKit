import XCTest

@testable import Agent

class ParseGeminiMessageTests: XCTestCase {
    func testParseGeminiModelMessage() {
        let data = """
        {
            "role": "model",
            "parts": [
                {
                    "text": "Hello! How can I help you today?"
                }
            ]
        }
        """

        let message = try! JSONDecoder().decode(GeminiMessage.self, from: data.data(using: .utf8)!)
        if case .model(let modelMessage) = message {
            XCTAssertEqual(modelMessage.parts.count, 1)
            if case .text(let textPart) = modelMessage.parts[0] {
                XCTAssertEqual(textPart.text, "Hello! How can I help you today?")
            } else {
                XCTFail("Part is not a text part")
            }
        } else {
            XCTFail("Message is not a model message")
        }
    }

    func testParseGeminiUserMessage() {
        let data = """
        {
            "role": "user",
            "parts": [
                {
                    "text": "What is the weather?"
                }
            ]
        }
        """

        let message = try! JSONDecoder().decode(GeminiMessage.self, from: data.data(using: .utf8)!)
        if case .user(let userMessage) = message {
            XCTAssertEqual(userMessage.parts.count, 1)
            if case .text(let textPart) = userMessage.parts[0] {
                XCTAssertEqual(textPart.text, "What is the weather?")
            } else {
                XCTFail("Part is not a text part")
            }
        } else {
            XCTFail("Message is not a user message")
        }
    }

    func testParseGeminiFunctionCallMessage() {
        let data = """
        {
            "role": "model",
            "parts": [
                {
                    "functionCall": {
                        "name": "getWeather",
                        "args": {
                            "city": "San Francisco"
                        }
                    }
                }
            ]
        }
        """

        let message = try! JSONDecoder().decode(GeminiMessage.self, from: data.data(using: .utf8)!)
        if case .model(let modelMessage) = message {
            XCTAssertEqual(modelMessage.parts.count, 1)
            if case .functionCall(let functionCall) = modelMessage.parts[0] {
                XCTAssertEqual(functionCall.name, "getWeather")
                XCTAssertEqual(functionCall.args["city"], "San Francisco")
            } else {
                XCTFail("Part is not a function call part")
            }
        } else {
            XCTFail("Message is not a model message")
        }
    }

    func testParseGeminiInlineDataMessage() {
        let data = """
        {
            "role": "user",
            "parts": [
                {
                    "inlineData": {
                        "mimeType": "image/jpeg",
                        "data": "base64encodeddata"
                    }
                }
            ]
        }
        """

        let message = try! JSONDecoder().decode(GeminiMessage.self, from: data.data(using: .utf8)!)
        if case .user(let userMessage) = message {
            XCTAssertEqual(userMessage.parts.count, 1)
            if case .inlineData(let inlineData) = userMessage.parts[0] {
                XCTAssertEqual(inlineData.mimeType, "image/jpeg")
                XCTAssertEqual(inlineData.data, "base64encodeddata")
            } else {
                XCTFail("Part is not an inline data part")
            }
        } else {
            XCTFail("Message is not a user message")
        }
    }

    func testSerializeGeminiMessages() {
        let userMessage = GeminiUserMessage(text: "Hello")
        let modelMessage = GeminiModelMessage(text: "Hi there!")

        let messages: [GeminiMessage] = [
            .user(userMessage),
            .model(modelMessage)
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(messages)
        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertNotNil(jsonString)
    }

    func testSerializeGeminiRequest() {
        let contents = [
            GeminiContent(
                role: .user,
                parts: [.text(GeminiTextPart(text: "Hello"))]
            )
        ]
        
        let systemInstruction = GeminiContent(
            role: nil,
            parts: [.text(GeminiTextPart(text: "You are a helpful assistant."))]
        )
        
        let tools = [
            GeminiTool(functionDeclarations: [
                GeminiTool.FunctionDeclaration(
                    name: "getWeather",
                    description: "Get weather by city",
                    parameters: .object(
                        title: "weather",
                        properties: [
                            "city": .string(description: "name of the city")
                        ],
                        required: ["city"]
                    )
                )
            ])
        ]
        
        let request = GeminiRequest(
            contents: contents,
            tools: tools,
            systemInstruction: systemInstruction
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(request)
        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertNotNil(jsonString)
        
        // Verify we can decode it back
        let decoder = JSONDecoder()
        let decodedRequest = try! decoder.decode(GeminiRequest.self, from: data)
        XCTAssertEqual(decodedRequest.contents.count, 1)
        XCTAssertNotNil(decodedRequest.systemInstruction)
        XCTAssertEqual(decodedRequest.tools?.count, 1)
    }
}
