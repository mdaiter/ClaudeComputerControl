import Foundation

public final class OpenAILLMClient: LLMClient, @unchecked Sendable {
    public let model: String
    private let apiKey: String
    private let apiURL = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession

    public init(model: LLMModel, apiKey: String? = nil) throws {
        self.model = model.rawValue

        if let key = apiKey {
            self.apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            self.apiKey = envKey
        } else {
            throw LLMError.apiKeyMissing
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    public func complete(prompt: String, systemPrompt: String?) async throws -> String {
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var messages: [[String: String]] = []
        if let systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        return content
    }
}
