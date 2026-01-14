import Foundation
import SwiftTUI

/// Main application for exploring Swift APIs in binaries.
@MainActor
public final class ExplorerApp {
    private let catalog: APICatalog

    public init(catalog: APICatalog) {
        self.catalog = catalog
    }

    /// Runs the interactive TUI explorer.
    public func run() {
        Application(rootView: ExplorerView(catalog: catalog)).start()
    }

    /// Exports the catalog to a JSON file.
    public func export(to path: String) throws {
        let json = try catalog.toJSONString()
        try json.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
