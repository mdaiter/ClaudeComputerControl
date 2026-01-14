import Foundation

/// Protocol for LLM client implementations.
public protocol LLMClient: Sendable {
    /// The model identifier being used.
    var model: String { get }

    /// Generates a completion for the given prompt.
    func complete(prompt: String, systemPrompt: String?) async throws -> String
}

/// Supported LLM models.
public enum LLMModel: String, CaseIterable, Sendable {
    case claudeSonnet = "claude-sonnet-4-20250514"
    case claudeOpus = "claude-opus-4-5-20250520"

    public var displayName: String {
        switch self {
        case .claudeSonnet: return "Claude Sonnet 4"
        case .claudeOpus: return "Claude Opus 4.5"
        }
    }
}

/// Error types for LLM operations.
public enum LLMError: Error, LocalizedError {
    case apiKeyMissing
    case requestFailed(String)
    case invalidResponse
    case rateLimited
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ANTHROPIC_API_KEY environment variable not set"
        case .requestFailed(let message):
            return "API request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited:
            return "Rate limited by API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
