//
//  geminiClient.swift
//  AgentKit
//
//  Created by Copilot
//

import Foundation

enum GeminiError: LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(url: URL, textResponse: String)
    case decodingError
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse(let url, let textResponse):
            return "Invalid response from server.\n URL: \(url)\n Response: \(textResponse)"
        case .decodingError:
            return "Failed to decode response."
        case .missingAPIKey:
            return "API key is required for Gemini API."
        }
    }
}

struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let tools: [GeminiTool]?
    let systemInstruction: GeminiContent?
    
    enum CodingKeys: String, CodingKey {
        case contents
        case tools
        case systemInstruction
    }
    
    init(contents: [GeminiContent], tools: [GeminiTool]? = nil, systemInstruction: GeminiContent? = nil) {
        self.contents = contents
        self.tools = tools
        self.systemInstruction = systemInstruction
    }
}

struct GeminiResponse: Codable {
    struct Candidate: Codable {
        let content: GeminiContent
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case content
            case finishReason
        }
    }
    
    let candidates: [Candidate]
}

actor GeminiClient {
    private let apiKey: String
    private let baseURL: URL
    
    init(baseURL: URL, apiKey: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
    
    func makeRequest(
        model: String,
        body: GeminiRequest
    ) async throws -> URLSession.AsyncBytes {
        // Gemini API endpoint format: {baseURL}/v1beta/models/{model}:streamGenerateContent?key={apiKey}
        let endpoint = baseURL
            .appendingPathComponent("v1beta/models/\(model):streamGenerateContent")
        
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) else {
            throw GeminiError.invalidURL
        }
        
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = components.url else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (responseStream, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let textResponse = response.description
            throw GeminiError.invalidResponse(url: url, textResponse: textResponse)
        }
        
        return responseStream
    }
    
    func generateStreamResponse(
        systemText: String?,
        message: GeminiUserMessage,
        model: OpenAICompatibleModel,
        tools: [GeminiTool] = [],
        history: [GeminiMessage] = []
    )
        -> (stream: AsyncThrowingStream<GeminiMessage, Error>, cancellable: Cancellable)
    {
        let task = Task<Void, Never> {}
        let stream = AsyncThrowingStream<GeminiMessage, Error> { continuation in
            Task {
                do {
                    var contents: [GeminiContent] = []
                    
                    // Add history (excluding system messages as they go in systemInstruction)
                    for msg in history {
                        contents.append(GeminiContent(role: msg.role, parts: msg.parts))
                    }
                    
                    // Add current user message
                    contents.append(GeminiContent(role: .user, parts: message.parts))
                    
                    // Create system instruction if provided
                    let systemInstruction: GeminiContent? = systemText.map {
                        GeminiContent(role: nil, parts: [.text(GeminiTextPart(text: $0))])
                    }
                    
                    let requestBody = GeminiRequest(
                        contents: contents,
                        tools: tools.isEmpty ? nil : tools,
                        systemInstruction: systemInstruction
                    )
                    
                    let responseStream = try await makeRequest(model: model.id, body: requestBody)
                    var totalText = ""
                    var totalParts: [GeminiPart] = []
                    
                    for try await line in responseStream.lines {
                        if task.isCancelled {
                            continuation.finish()
                            break
                        }
                        
                        // Skip empty lines
                        guard !line.isEmpty else { continue }
                        
                        // Gemini streaming response comes as JSON objects separated by newlines
                        if let data = line.data(using: .utf8),
                           let response = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                           let candidate = response.candidates.first
                        {
                            let content = candidate.content
                            
                            // Accumulate text parts
                            for part in content.parts {
                                if case .text(let textPart) = part {
                                    totalText += textPart.text
                                    totalParts.append(.text(GeminiTextPart(text: totalText)))
                                } else {
                                    totalParts.append(part)
                                }
                            }
                            
                            // Yield the accumulated message
                            let message = GeminiModelMessage(parts: totalParts)
                            continuation.yield(.model(message))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        return (stream, Cancellable { task.cancel() })
    }
}
