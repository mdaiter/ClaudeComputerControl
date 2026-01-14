import Foundation

/// Exports API catalogs to various formats for LLM consumption.
public struct ControlLayerExporter: Sendable {
    public init() {}

    /// Exports the catalog to a JSON file.
    public func exportJSON(_ catalog: APICatalog, to path: String) throws {
        let json = try catalog.toJSONString()
        try json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Exports the catalog to a compact JSON format (minimal whitespace).
    public func exportCompactJSON(_ catalog: APICatalog) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return string
    }

    /// Exports a summary suitable for LLM context windows.
    public func exportSummary(_ catalog: APICatalog, maxAPIs: Int = 100) -> String {
        var output = """
        # API Catalog Summary
        Binary: \(catalog.binaryPath)
        Extracted: \(ISO8601DateFormatter().string(from: catalog.extractedAt))

        ## Statistics
        - Types: \(catalog.stats.typeCount)
        - Protocols: \(catalog.stats.protocolCount)
        - Functions: \(catalog.stats.functionCount)
        - Total APIs: \(catalog.stats.totalAPIs)
        - Average Certainty: \(String(format: "%.1f", catalog.averageCertainty))

        ## Certainty Distribution
        \(catalog.certaintyDistribution.description)

        ## Top APIs (by certainty)

        """

        let topAPIs = Array(catalog.allAPIs.prefix(maxAPIs))
        for api in topAPIs {
            output += "[\(String(format: "%2d", api.certainty.score))] \(api.signature)\n"
        }

        if catalog.allAPIs.count > maxAPIs {
            output += "\n... and \(catalog.allAPIs.count - maxAPIs) more APIs\n"
        }

        return output
    }

    /// Exports a single API entry for LLM sample generation context.
    public func exportAPIContext(_ api: APIEntry) -> String {
        var context = """
        ## API Details
        ID: \(api.id)
        Kind: \(api.kind.rawValue)
        Signature: \(api.signature)
        Certainty Score: \(api.certainty.score)/100
        Complexity Factors: \(api.certainty.explanation)

        """

        if let parent = api.parentType {
            context += "Parent Type: \(parent)\n"
        }

        if !api.children.isEmpty {
            context += "\n### Members (\(api.children.count)):\n"
            for child in api.children.prefix(20) {
                context += "- \(child.signature)\n"
            }
        }

        return context
    }
}

public enum ExportError: Error, LocalizedError {
    case encodingFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode catalog to JSON"
        case .writeFailed(let path):
            return "Failed to write to: \(path)"
        }
    }
}
