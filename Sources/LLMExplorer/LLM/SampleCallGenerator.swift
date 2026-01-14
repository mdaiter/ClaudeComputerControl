import Foundation

/// Generates sample API calls using an LLM.
public actor SampleCallGenerator {
    private let client: LLMClient
    private let promptBuilder: PromptBuilder
    private var cache: [String: String] = [:]

    public init(client: LLMClient) {
        self.client = client
        self.promptBuilder = PromptBuilder()
    }

    /// Generates a sample call for the given API.
    public func generateSample(for api: APIEntry, context: APICatalog? = nil) async throws -> GeneratedSample {
        // Check cache first
        if let cached = cache[api.id] {
            return GeneratedSample(api: api, code: cached, fromCache: true)
        }

        let prompt = promptBuilder.buildSampleCallPrompt(for: api, context: context)
        let response = try await client.complete(
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt
        )

        // Extract code from response
        let code = extractCode(from: response)

        // Cache the result
        cache[api.id] = code

        return GeneratedSample(api: api, code: code, fromCache: false)
    }

    /// Generates an exploration analysis for the given API.
    public func exploreAPI(_ api: APIEntry, catalog: APICatalog) async throws -> String {
        let prompt = promptBuilder.buildExplorationPrompt(for: api, catalog: catalog)
        return try await client.complete(
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt
        )
    }

    /// Generates a test case for the given API.
    public func generateTestCase(for api: APIEntry) async throws -> String {
        let prompt = promptBuilder.buildTestCasePrompt(for: api)
        return try await client.complete(
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt
        )
    }

    /// Clears the sample cache.
    public func clearCache() {
        cache.removeAll()
    }

    /// Extracts Swift code from an LLM response.
    private func extractCode(from response: String) -> String {
        // Look for code blocks
        let patterns = [
            #"```swift\n([\s\S]*?)```"#,
            #"```\n([\s\S]*?)```"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
               let range = Range(match.range(at: 1), in: response) {
                return String(response[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // If no code block found, return the full response
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Represents a generated sample call.
public struct GeneratedSample: Sendable {
    /// The API this sample is for.
    public let api: APIEntry

    /// The generated Swift code.
    public let code: String

    /// Whether this result came from cache.
    public let fromCache: Bool

    /// Formatted output for display.
    public var displayOutput: String {
        """
        // Sample for: \(api.name)
        // Certainty: \(api.certainty.score)/100
        \(fromCache ? "// (cached)" : "")

        \(code)
        """
    }
}
