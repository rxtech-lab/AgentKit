import Foundation
import Testing

@testable import Agent

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

func setUpTests() async throws -> (AgentClient, Source, Model) {
    let env = loadEnv()
    let apiKey = env["OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    let endpoint =
        env["OPENAI_API_BASE_URL"] ?? ProcessInfo.processInfo.environment["OPENAI_API_BASE_URL"]
    let modelName = env["OPENAI_MODEL"] ?? ProcessInfo.processInfo.environment["OPENAI_MODEL"]

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
    let baseURL = URL(string: endpoint)!
    let source = Source.openRouter(
        client: OpenRouterClient(apiKey: apiKey, baseURL: baseURL),
        models: []
    )
    let client = AgentClient()
    let model = Model.custom(CustomModel(id: modelName))
    return (client, source, model)
}
