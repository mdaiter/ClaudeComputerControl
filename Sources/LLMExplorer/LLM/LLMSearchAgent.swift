import Foundation

/// Uses an LLM to expand natural-language queries into catalog searches.
public actor LLMSearchAgent {
    private let client: LLMClient
    private let maxKeywords: Int

    public init(client: LLMClient, maxKeywords: Int = 5) {
        self.client = client
        self.maxKeywords = max(1, maxKeywords)
    }

    /// Returns catalog entries relevant to the user's query.
    public func search(query: String, in catalog: APICatalog, limit: Int = 200) async throws -> [APIEntry] {
        let prompt = buildPrompt(query: query, catalog: catalog)
        let response = try await client.complete(
            prompt: prompt,
            systemPrompt: PromptBuilder.systemPrompt
        )

        let keywords = parseKeywords(from: response, fallback: query)
        return collectResults(using: keywords, catalog: catalog, limit: limit)
    }

    private func buildPrompt(query: String, catalog: APICatalog) -> String {
        let sampleAPIs = catalog.topLevelAPIs.prefix(40).map { "- \($0.signature)" }.joined(separator: "\n")

        return """
        You help map natural language requests to Swift APIs extracted from binaries.

        Catalog summary:
        \(catalog.stats.summary) (total APIs: \(catalog.stats.totalAPIs))

        Sample APIs:
        \(sampleAPIs)

        Developer query: "\(query)"

        Return a JSON array (e.g. ["keyword one","keyword two"]) with up to \(maxKeywords) short keywords or symbol fragments that best describe APIs matching the query. Focus on nouns/verbs developers would search for, like type names, subsystem names, or tasks.

        Respond ONLY with the JSON array.
        """
    }

    private func parseKeywords(from response: String, fallback: String) -> [String] {
        var candidates: [String] = []
        if let data = response.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            candidates = array
        } else {
            let separators = CharacterSet(charactersIn: ",\n")
            candidates = response.components(separatedBy: separators)
        }
        let cleaned = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            return [fallback]
        }
        var result = [fallback]
        for item in cleaned where !result.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
            result.append(item)
        }
        return result
    }

    private func collectResults(using terms: [String], catalog: APICatalog, limit: Int) -> [APIEntry] {
        var results: [APIEntry] = []
        var seenIDs = Set<String>()

        for term in terms {
            let matches = catalog.search(query: term)
            for entry in matches {
                if seenIDs.insert(entry.id).inserted {
                    results.append(entry)
                    if results.count >= limit {
                        return results
                    }
                }
            }
            if results.count >= limit {
                break
            }
        }

        return results
    }
}
