import Foundation

/// Main application for exploring Swift APIs in binaries.
/// Provides both TUI and console-based output modes.
@MainActor
public final class ExplorerApp {
    private let catalog: APICatalog
    private var filteredAPIs: [APIEntry]
    private var selectedIndex: Int = 0

    public init(catalog: APICatalog) {
        self.catalog = catalog
        self.filteredAPIs = catalog.allAPIs
    }

    /// Runs the interactive explorer.
    /// Falls back to console mode if TUI is not available.
    public func run() {
        runConsoleMode()
    }

    /// Runs in console mode with basic navigation.
    private func runConsoleMode() {
        print("\n=== Swift API Explorer ===")
        print("Binary: \(catalog.binaryPath)")
        print("Stats: \(catalog.stats.summary)")
        print("Average Certainty: \(String(format: "%.1f", catalog.averageCertainty))")
        print("Distribution: \(catalog.certaintyDistribution.description)")
        print("")

        // Show top APIs
        let topAPIs = Array(catalog.allAPIs.prefix(50))
        print("Top 50 APIs by Certainty:")
        print("-" * 60)

        for (index, api) in topAPIs.enumerated() {
            let marker = index == selectedIndex ? ">" : " "
            print("\(marker) \(api.listDisplayString)")
            if !api.signature.isEmpty && api.signature != api.name {
                print("    \(api.signature)")
            }
        }

        print("-" * 60)
        print("\nTo export full catalog, use --output-path flag")
        print("Total APIs: \(catalog.allAPIs.count)")
    }

    /// Shows details for a specific API.
    public func showDetails(for api: APIEntry) {
        print("\n=== API Details ===")
        print("ID: \(api.id)")
        print("Kind: \(api.kind.displayName)")
        print("Signature: \(api.signature)")
        print("Certainty: \(api.certainty.score)/100")
        print("Factors: \(api.certainty.explanation)")

        if let parent = api.parentType {
            print("Parent: \(parent)")
        }

        if let offset = api.offset {
            print("Offset: \(offset)")
        }

        if !api.children.isEmpty {
            print("\nMembers (\(api.children.count)):")
            for child in api.children.prefix(20) {
                print("  [\(child.certainty.score)] \(child.name)")
            }
            if api.children.count > 20 {
                print("  ... and \(api.children.count - 20) more")
            }
        }
    }

    /// Searches APIs by query.
    public func search(query: String) -> [APIEntry] {
        catalog.search(query: query)
    }

    /// Exports the catalog to a JSON file.
    public func export(to path: String) throws {
        let json = try catalog.toJSONString()
        try json.write(toFile: path, atomically: true, encoding: .utf8)
        print("Exported catalog to: \(path)")
    }
}

// Simple string multiplication for formatting
private func * (string: String, count: Int) -> String {
    String(repeating: string, count: count)
}
