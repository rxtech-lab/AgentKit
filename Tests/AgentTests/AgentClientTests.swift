import XCTest
import Vapor
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
        
        source = Source(displayName: "Test", endpoint: "http://localhost:\(port)", apiKey: "test", apiType: .openAI)
        agentClient = AgentClient()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        controller = nil
    }

    func testMultiTurnConversationWithTools() async throws {
        // 1. Setup Tools
        let weatherTool = AgentTool(
            name: "get_weather",
            description: "Get weather",
            parameters: .object(properties: ["location": .string()], required: ["location"])
        ) { args in
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
        let msg2 = OpenAIAssistantMessage(content: "It is sunny in Paris.", toolCalls: nil, audio: nil)
        
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
}

