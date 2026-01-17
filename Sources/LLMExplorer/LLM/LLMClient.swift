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
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    public var displayName: String {
        switch self {
        case .claudeSonnet: return "Claude Sonnet 4"
        case .claudeOpus: return "Claude Opus 4.5"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        }
    }

    public var provider: LLMProvider {
        switch self {
        case .claudeSonnet, .claudeOpus:
            return .anthropic
        case .gpt4o, .gpt4oMini:
            return .openAI
        }
    }
}

public enum LLMProvider {
    case anthropic
    case openAI
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
            return "LLM API key not set (configure ANTHROPIC_API_KEY or OPENAI_API_KEY)"
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
