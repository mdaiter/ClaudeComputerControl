import SwiftTUI

struct ExplorerView: View {
    @ObservedObject var viewModel: ExplorerViewModel

    var body: some View {
        VStack {
            header
            Spacer()
            HStack(alignment: .top) {
                apiList
                if let api = viewModel.selectedAPI {
                    detailPanel(api)
                }
            }
            Spacer()
            footer
        }
        .padding(1)
    }

    private var header: some View {
        VStack {
            Text("Swift API Explorer")
                .bold()
            Text(viewModel.catalog.binaryPath)
                .foregroundColor(.cyan)
            HStack {
                Text("\(viewModel.catalog.stats.typeCount) types")
                Text("\(viewModel.catalog.stats.protocolCount) protocols")
                Text("\(viewModel.catalog.stats.functionCount) functions")
                Text("avg: \(Int(viewModel.catalog.averageCertainty))")
            }
            .foregroundColor(.gray)
        }
    }

    private var apiList: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("/")
                    .foregroundColor(.gray)
                TextField(
                    placeholder: viewModel.searchMode.placeholder,
                    onFocusChange: { viewModel.setSearchFieldFocus($0) }
                ) { query in
                    viewModel.submitSearch(query)
                }
                Button(action: viewModel.toggleSearchMode) {
                    Text(viewModel.searchMode.displayName)
                        .foregroundColor(viewModel.searchMode == .keyword ? .green : .magenta)
                }
            }
            searchStatus
            if viewModel.visibleAPIs.isEmpty {
                Text(emptyStateMessage)
                    .foregroundColor(.gray)
                    .padding(.vertical, 1)
            } else {
                ForEach(viewModel.visibleAPIs) { api in
                    Button(
                        action: { viewModel.selectAPI(api) },
                        hover: { viewModel.selectAPI(api) }
                    ) {
                        let isSelected = viewModel.selectedAPI?.id == api.id
                        HStack {
                            Text(isSelected ? "▸" : " ")
                                .foregroundColor(.cyan)
                            Text("[\(api.certainty.score)]")
                                .foregroundColor(colorForScore(api.certainty.score))
                            if isSelected {
                                Text(api.name)
                                    .bold()
                                    .foregroundColor(.white)
                            } else {
                                Text(api.name)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
        .frame(minWidth: 40)
    }

    private func detailPanel(_ api: APIEntry) -> some View {
        VStack(alignment: .leading) {
            Text(api.kind.displayName.uppercased())
                .foregroundColor(.yellow)
                .bold()
            Text(api.signature)
                .foregroundColor(.white)
            Spacer()
            Text("Certainty: \(api.certainty.score)/100")
            Text(api.certainty.explanation)
                .foregroundColor(.gray)
            if let offset = api.offset {
                Text("Offset: \(offset)")
                    .foregroundColor(.gray)
            }
            if !api.children.isEmpty {
                Spacer()
                Text("Members: \(api.children.count)")
                    .foregroundColor(.gray)
            }
            Spacer()
            sampleSection(for: api)
        }
        .padding(.horizontal, 2)
        .frame(minWidth: 30)
        .border()
    }

    private func sampleSection(for api: APIEntry) -> some View {
        VStack(alignment: .leading) {
            if viewModel.isGeneratingSample {
                Text("Generating example with LLM…")
                    .foregroundColor(.cyan)
            } else if let sample = viewModel.generatedSample, sample.api.id == api.id {
                Text("Example usage:")
                    .bold()
                    .foregroundColor(.green)
                let lines = codeLines(for: sample.code)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.0) { pair in
                            Button(action: {}, hover: {}) {
                                Text(pair.1)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .frame(height: 12)
                .border()
                Text("Focus the code box and use ↑/↓ to scroll.")
                    .foregroundColor(.gray)
            } else if let error = viewModel.generationError {
                Text("Example unavailable: \(error)")
                    .foregroundColor(.red)
            } else {
                Text("Press Ctrl+E to generate an example")
                    .foregroundColor(.gray)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("[up/down] Navigate")
            Text("[/] Search")
            Text("[Ctrl+L] Toggle mode")
            Text("[Ctrl+E] Example")
            Text("[Ctrl+D] Quit")
        }
        .foregroundColor(.gray)
    }

    private var searchStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.searchMode {
            case .keyword:
                Text("Keyword search (press Return to filter)")
                    .foregroundColor(.gray)
            case .llm:
                if viewModel.isLLMSearching {
                    Text("LLM search in progress...")
                        .foregroundColor(.cyan)
                } else if let error = viewModel.llmSearchError {
                    Text(error)
                        .foregroundColor(.red)
                } else if viewModel.hasLLMResults {
                    Text("LLM search results (\(viewModel.visibleAPIs.count) shown)")
                        .foregroundColor(.gray)
                } else {
                    Text("Describe what you need and press Return to ask the LLM.")
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var emptyStateMessage: String {
        switch viewModel.searchMode {
        case .keyword:
            return viewModel.searchQuery.isEmpty ? "No APIs available." : "No APIs matched \"\(viewModel.searchQuery)\"."
        case .llm:
            if viewModel.searchQuery.isEmpty {
                return "Enter a description to run LLM search."
            } else if viewModel.isLLMSearching {
                return "Searching..."
            } else if let error = viewModel.llmSearchError {
                return error
            } else {
                return "LLM did not find relevant APIs."
            }
        }
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private func codeLines(for code: String) -> [String] {
        code.components(separatedBy: .newlines)
    }
}
