import Foundation

/// Represents a complete catalog of APIs extracted from a binary.
public struct APICatalog: Codable, Sendable {
    /// Path to the binary that was analyzed
    public let binaryPath: String

    /// Timestamp of extraction
    public let extractedAt: Date

    /// All type definitions (structs, classes, enums)
    public var types: [APIEntry]

    /// All protocol definitions
    public var protocols: [APIEntry]

    /// All global functions
    public var globalFunctions: [APIEntry]

    /// All global variables
    public var globalVariables: [APIEntry]

    /// Summary statistics
    public var stats: CatalogStats

    public init(
        binaryPath: String,
        extractedAt: Date = Date(),
        types: [APIEntry] = [],
        protocols: [APIEntry] = [],
        globalFunctions: [APIEntry] = [],
        globalVariables: [APIEntry] = []
    ) {
        self.binaryPath = binaryPath
        self.extractedAt = extractedAt
        self.types = types
        self.protocols = protocols
        self.globalFunctions = globalFunctions
        self.globalVariables = globalVariables
        self.stats = CatalogStats(
            typeCount: types.count,
            protocolCount: protocols.count,
            functionCount: globalFunctions.count,
            variableCount: globalVariables.count,
            totalAPIs: types.flatMap(\.flattened).count +
                       protocols.flatMap(\.flattened).count +
                       globalFunctions.count +
                       globalVariables.count
        )
    }

    /// All APIs as a flat list, sorted by certainty
    public var allAPIs: [APIEntry] {
        var all: [APIEntry] = []
        all.append(contentsOf: types.flatMap(\.flattened))
        all.append(contentsOf: protocols.flatMap(\.flattened))
        all.append(contentsOf: globalFunctions)
        all.append(contentsOf: globalVariables)
        return APIEntry.sortedByCertainty(all)
    }

    /// Top-level APIs only (types, protocols, global functions/vars)
    public var topLevelAPIs: [APIEntry] {
        var all: [APIEntry] = []
        all.append(contentsOf: types)
        all.append(contentsOf: protocols)
        all.append(contentsOf: globalFunctions)
        all.append(contentsOf: globalVariables)
        return APIEntry.sortedByCertainty(all)
    }

    /// Search all APIs
    public func search(query: String) -> [APIEntry] {
        APIEntry.search(allAPIs, query: query)
    }

    /// Filter by minimum certainty
    public func filtered(minCertainty: Int) -> [APIEntry] {
        APIEntry.filtered(allAPIs, minCertainty: minCertainty)
    }

    /// Get APIs by kind
    public func apis(ofKind kind: APIKind) -> [APIEntry] {
        allAPIs.filter { $0.kind == kind }
    }

    /// Average certainty score
    public var averageCertainty: Double {
        let all = allAPIs
        guard !all.isEmpty else { return 0 }
        return Double(all.reduce(0) { $0 + $1.certainty.score }) / Double(all.count)
    }

    /// Distribution of certainty scores
    public var certaintyDistribution: CertaintyDistribution {
        let all = allAPIs
        return CertaintyDistribution(
            high: all.filter { $0.certainty.score >= 80 }.count,
            medium: all.filter { $0.certainty.score >= 40 && $0.certainty.score < 80 }.count,
            low: all.filter { $0.certainty.score < 40 }.count
        )
    }
}

/// Summary statistics for a catalog
public struct CatalogStats: Codable, Sendable {
    public let typeCount: Int
    public let protocolCount: Int
    public let functionCount: Int
    public let variableCount: Int
    public let totalAPIs: Int

    public init(
        typeCount: Int,
        protocolCount: Int,
        functionCount: Int,
        variableCount: Int,
        totalAPIs: Int
    ) {
        self.typeCount = typeCount
        self.protocolCount = protocolCount
        self.functionCount = functionCount
        self.variableCount = variableCount
        self.totalAPIs = totalAPIs
    }

    public var summary: String {
        "\(typeCount) types, \(protocolCount) protocols, \(functionCount) functions"
    }
}

/// Distribution of certainty scores
public struct CertaintyDistribution: Codable, Sendable {
    /// APIs with certainty >= 80
    public let high: Int
    /// APIs with certainty 40-79
    public let medium: Int
    /// APIs with certainty < 40
    public let low: Int

    public var description: String {
        "High: \(high), Medium: \(medium), Low: \(low)"
    }
}

extension APICatalog {
    /// JSON encoder configured for control layer output
    public static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encode to JSON data
    public func toJSON() throws -> Data {
        try Self.jsonEncoder.encode(self)
    }

    /// Encode to JSON string
    public func toJSONString() throws -> String {
        let data = try toJSON()
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(data, .init(codingPath: [], debugDescription: "Failed to convert JSON data to string"))
        }
        return string
    }
}
