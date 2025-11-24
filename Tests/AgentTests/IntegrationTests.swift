import Foundation
import Testing

@testable import Agent

struct IntegrationTests {
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
                            let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
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
        let env = loadEnv()
        let apiKey = env["OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("Skipping integration test: OPENAI_API_KEY not found in .env or environment")
            return
        }
        
        let endpoint = env["OPENAI_API_BASE_URL"] ?? "https://api.openai.com/v1"
        let modelName = env["OPENAI_MODEL"] ?? "gpt-3.5-turbo"

        // 2. Setup AgentClient and Source
        let source = Source(
            displayName: "OpenAI",
            endpoint: endpoint,
            apiKey: apiKey,
            apiType: .openAI
        )
        let client = AgentClient()

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
                    "b": .integer(description: "Second number")
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
                       !toolCalls.isEmpty {
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
                       let content = assistantMsg.content {
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
}

