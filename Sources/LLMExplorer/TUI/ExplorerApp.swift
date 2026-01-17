import Foundation
import SwiftTUI

/// Main application for exploring Swift APIs in binaries.
@MainActor
public final class ExplorerApp {
    private enum ControlKeys {
        static let toggleSearch: Character = "\u{0c}" // Ctrl+L
        static let example: Character = "\u{05}" // Ctrl+E
    }

    private let catalog: APICatalog
    private let viewModel: ExplorerViewModel
    private let sampleGenerator: SampleCallGenerator?
    private let searchAgent: LLMSearchAgent?

    public init(catalog: APICatalog, sampleGenerator: SampleCallGenerator? = nil, searchAgent: LLMSearchAgent? = nil) {
        self.catalog = catalog
        self.viewModel = ExplorerViewModel(catalog: catalog)
        self.sampleGenerator = sampleGenerator
        self.searchAgent = searchAgent

        if let first = viewModel.visibleAPIs.first {
            self.viewModel.selectAPI(first)
        }

        viewModel.configureLLMSearch(available: searchAgent != nil) { [weak self] query in
            self?.performLLMSearch(query: query)
        }
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
        app.onNavigationKey = { [weak self] key in
            self?.handleNavigationKey(key) ?? false
        }
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

    private func handleNavigationKey(_ key: Application.NavigationKey) -> Bool {
        switch key {
        case .down:
            return viewModel.moveSelection(by: 1)
        case .up:
            return viewModel.moveSelection(by: -1)
        default:
            return false
        }
    }

    private func handleKeyPress(_ char: Character) -> Bool {
        if char == ControlKeys.toggleSearch {
            viewModel.toggleSearchMode()
            return true
        }
        if char == ControlKeys.example {
            handleExampleHotkey()
            return true
        }
        if viewModel.isSearchFieldFocused {
            return false
        }
        return false
    }

    private func performLLMSearch(query: String) {
        guard let searchAgent else {
            viewModel.handleLLMSearchFailure("LLM search unavailable.")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await searchAgent.search(query: query, in: catalog)
                await MainActor.run {
                    self.viewModel.handleLLMSearchResults(results)
                }
            } catch {
                await MainActor.run {
                    self.viewModel.handleLLMSearchFailure(error.localizedDescription)
                }
            }
        }
    }

    private func handleExampleHotkey() {
        guard let api = viewModel.selectedAPI else {
            viewModel.failSampleRequest(message: "Select an API first")
            return
        }
        guard let generator = sampleGenerator else {
            viewModel.failSampleRequest(message: "LLM unavailable (set ANTHROPIC_API_KEY or OPENAI_API_KEY)")
            return
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
    }
}
