import Foundation

/// Claude API client implementation.
public final class ClaudeLLMClient: LLMClient, @unchecked Sendable {
    public let model: String
    private let apiKey: String
    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession

    public init(model: LLMModel = .claudeSonnet, apiKey: String? = nil) throws {
        self.model = model.rawValue

        // Get API key from parameter or environment
        if let key = apiKey {
            self.apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            self.apiKey = envKey
        } else {
            throw LLMError.apiKeyMissing
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    public func complete(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let request = try buildRequest(prompt: prompt, systemPrompt: systemPrompt)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw LLMError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try parseResponse(data)
    }

    private func buildRequest(prompt: String, systemPrompt: String?) throws -> URLRequest {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse
        }
        return text
    }
}
