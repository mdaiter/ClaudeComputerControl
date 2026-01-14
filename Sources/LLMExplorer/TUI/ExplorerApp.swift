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
    public func run() async {
        #if os(macOS)
        // Swift Concurrency already owns the dispatch main loop, so we run
        // SwiftTUI in cooperative mode and let the host keep the process alive.
        let runLoopType: Application.RunLoopType = .cooperative
        #else
        let runLoopType: Application.RunLoopType = .dispatch
        #endif

        let app = Application(
            rootView: ExplorerView(catalog: catalog),
            runLoopType: runLoopType
        )

        if runLoopType == .cooperative {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                app.onStop = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                app.start()
            }
        } else {
            app.start()
        }
    }

    /// Exports the catalog to a JSON file.
    public func export(to path: String) throws {
        let json = try catalog.toJSONString()
        try json.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
