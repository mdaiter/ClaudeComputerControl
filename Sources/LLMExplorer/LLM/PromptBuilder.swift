import Foundation

/// Builds prompts for LLM API exploration tasks.
public struct PromptBuilder: Sendable {
    private let exporter: ControlLayerExporter

    public init() {
        self.exporter = ControlLayerExporter()
    }

    /// System prompt for API exploration tasks.
    public static let systemPrompt = """
    You are a Swift API exploration assistant. Your task is to help developers understand and use Swift APIs extracted from compiled binaries.

    When generating sample code:
    1. Use proper Swift syntax
    2. Include necessary imports
    3. Handle optionals appropriately
    4. Add brief comments explaining non-obvious parts
    5. Consider error handling if the API throws

    When the certainty score is low (<50), warn about potential complexity and suggest starting with simpler approaches.

    Be concise but complete. Focus on working code that demonstrates the API's usage.
    """

    /// Builds a prompt for generating a sample call for an API.
    public func buildSampleCallPrompt(for api: APIEntry, context: APICatalog? = nil) -> String {
        var prompt = """
        Generate a Swift code sample that demonstrates how to use this API:

        \(exporter.exportAPIContext(api))

        """

        if let catalog = context {
            // Add relevant context about parent types if available
            if let parentName = api.parentType,
               let parentAPI = catalog.allAPIs.first(where: { $0.id == parentName }) {
                prompt += """

                Parent type information:
                \(parentAPI.signature)

                """
            }
        }

        prompt += """

        Please generate:
        1. A minimal working example showing how to call this API
        2. Brief comments explaining any non-obvious parameters
        3. If certainty is below 50, include a warning about potential complexity
        """

        return prompt
    }

    /// Builds a prompt for exploring related APIs.
    public func buildExplorationPrompt(for api: APIEntry, catalog: APICatalog) -> String {
        let relatedAPIs = findRelatedAPIs(for: api, in: catalog)

        var prompt = """
        Analyze this Swift API and suggest how it might be used:

        \(exporter.exportAPIContext(api))

        """

        if !relatedAPIs.isEmpty {
            prompt += """

            Related APIs in the same binary:
            """
            for related in relatedAPIs.prefix(10) {
                prompt += "\n- \(related.signature)"
            }
        }

        prompt += """

        Please provide:
        1. A brief explanation of what this API likely does
        2. Common use cases
        3. Potential pitfalls based on the complexity factors
        4. Related APIs that might be needed
        """

        return prompt
    }

    /// Builds a prompt for generating a test case.
    public func buildTestCasePrompt(for api: APIEntry) -> String {
        """
        Generate a Swift unit test for this API:

        \(exporter.exportAPIContext(api))

        Requirements:
        1. Use XCTest framework
        2. Test the happy path
        3. If the API throws, test error handling
        4. Use descriptive test method names
        5. Add assertions that verify expected behavior
        """
    }

    /// Finds APIs related to the given API.
    private func findRelatedAPIs(for api: APIEntry, in catalog: APICatalog) -> [APIEntry] {
        var related: [APIEntry] = []

        // If this is a member, include sibling members
        if let parentName = api.parentType,
           let parent = catalog.allAPIs.first(where: { $0.id == parentName }) {
            related.append(contentsOf: parent.children.filter { $0.id != api.id })
        }

        // Include APIs with similar names
        let nameParts = api.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for other in catalog.allAPIs where other.id != api.id {
            for part in nameParts where part.count > 3 {
                if other.name.lowercased().contains(part.lowercased()) {
                    related.append(other)
                    break
                }
            }
        }

        return Array(Set(related)).sorted { $0.certainty.score > $1.certainty.score }
    }
}
