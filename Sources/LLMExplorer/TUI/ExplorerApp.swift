import Foundation
import SwiftTUI

/// Main application for exploring Swift APIs in binaries.
@MainActor
public final class ExplorerApp {
    private let catalog: APICatalog
    private let viewModel: ExplorerViewModel
    private let sampleGenerator: SampleCallGenerator?

    public init(catalog: APICatalog, sampleGenerator: SampleCallGenerator? = nil) {
        self.catalog = catalog
        self.viewModel = ExplorerViewModel(catalog: catalog)
        self.sampleGenerator = sampleGenerator
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
            rootView: ExplorerView(viewModel: viewModel),
            runLoopType: runLoopType
        )
        app.onKeyPress = { [weak self] char in
            guard let self else { return false }
            return self.handleKeyPress(char)
        }

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

    private func handleKeyPress(_ char: Character) -> Bool {
        guard char == "e" || char == "E" else {
            return false
        }
        guard let api = viewModel.selectedAPI else {
            viewModel.failSampleRequest(message: "Select an API first")
            return true
        }
        guard let generator = sampleGenerator else {
            viewModel.failSampleRequest(message: "LLM unavailable (set ANTHROPIC_API_KEY)")
            return true
        }

        viewModel.beginSampleRequest()
        Task { [weak self] in
            guard let self else { return }
            do {
                let sample = try await generator.generateSample(for: api, context: catalog)
                await MainActor.run {
                    self.viewModel.finishSampleRequest(with: sample)
                }
            } catch {
                await MainActor.run {
                    self.viewModel.failSampleRequest(message: error.localizedDescription)
                }
            }
        }
        return true
    }
}
