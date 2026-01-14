import Foundation

/// Represents the complexity factors that contribute to an API's certainty score.
/// Higher scores indicate easier-to-call APIs.
public struct ComplexityFactors: Codable, Sendable, Hashable {
    /// Number of parameters (0 = easiest)
    public var parameterCount: Int

    /// Whether the function is async
    public var hasAsync: Bool

    /// Whether the function throws
    public var hasThrows: Bool

    /// Whether parameters or return type include closures
    public var hasClosures: Bool

    /// Nesting depth of the type (1 = top-level)
    public var nestingDepth: Int

    /// Number of generic type parameters
    public var genericParams: Int

    /// Whether return type is a stream or complex async type
    public var hasComplexReturnType: Bool

    /// Whether any parameter types are protocols or existentials
    public var hasProtocolParams: Bool

    public init(
        parameterCount: Int = 0,
        hasAsync: Bool = false,
        hasThrows: Bool = false,
        hasClosures: Bool = false,
        nestingDepth: Int = 1,
        genericParams: Int = 0,
        hasComplexReturnType: Bool = false,
        hasProtocolParams: Bool = false
    ) {
        self.parameterCount = parameterCount
        self.hasAsync = hasAsync
        self.hasThrows = hasThrows
        self.hasClosures = hasClosures
        self.nestingDepth = nestingDepth
        self.genericParams = genericParams
        self.hasComplexReturnType = hasComplexReturnType
        self.hasProtocolParams = hasProtocolParams
    }
}

/// Represents a certainty score for an API, indicating how easy it is to call.
/// Scores range from 0-100, with higher scores being easier to call.
public struct CertaintyScore: Codable, Sendable, Hashable, Comparable {
    /// The overall certainty score (0-100)
    public let score: Int

    /// The individual factors contributing to this score
    public let factors: ComplexityFactors

    /// Human-readable explanation of the score
    public var explanation: String {
        var parts: [String] = []

        if factors.parameterCount == 0 {
            parts.append("no params")
        } else if factors.parameterCount <= 3 {
            parts.append("\(factors.parameterCount) param(s)")
        } else {
            parts.append("many params (\(factors.parameterCount))")
        }

        if factors.hasAsync {
            parts.append("async")
        }

        if factors.hasThrows {
            parts.append("throws")
        }

        if factors.hasClosures {
            parts.append("closures")
        }

        if factors.genericParams > 0 {
            parts.append("\(factors.genericParams) generic(s)")
        }

        if factors.hasComplexReturnType {
            parts.append("complex return")
        }

        return parts.joined(separator: ", ")
    }

    public init(score: Int, factors: ComplexityFactors) {
        self.score = max(0, min(100, score))
        self.factors = factors
    }

    public static func < (lhs: CertaintyScore, rhs: CertaintyScore) -> Bool {
        lhs.score < rhs.score
    }

    /// Computes the certainty score from the given complexity factors.
    public static func compute(from factors: ComplexityFactors) -> CertaintyScore {
        var score = 100

        // Parameter count penalty (25 points max)
        switch factors.parameterCount {
        case 0: break // Full 25 points
        case 1...3: score -= 5
        case 4...6: score -= 15
        default: score -= 25
        }

        // Type complexity penalties (25 points max)
        if factors.hasClosures {
            score -= 20
        }
        if factors.genericParams > 0 {
            score -= min(15, factors.genericParams * 5)
        }
        if factors.hasProtocolParams {
            score -= 5
        }

        // Async/throws penalties (20 points max)
        if factors.hasAsync {
            score -= 5
        }
        if factors.hasThrows {
            score -= 10
        }

        // Nesting depth penalty (15 points max)
        switch factors.nestingDepth {
        case 1: break // Full 15 points
        case 2: score -= 3
        case 3: score -= 7
        default: score -= 12
        }

        // Return type complexity (15 points max)
        if factors.hasComplexReturnType {
            score -= 12
        }

        return CertaintyScore(score: score, factors: factors)
    }
}

extension CertaintyScore: CustomStringConvertible {
    public var description: String {
        "[\(score)]"
    }
}
