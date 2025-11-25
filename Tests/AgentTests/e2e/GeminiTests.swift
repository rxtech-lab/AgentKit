import Foundation
import Testing

@testable import Agent

struct GeminiTests {

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
            model: .custom(CustomModel(id: "google/gemini-3-pro-preview")),
            source: source,
            tools: []
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
