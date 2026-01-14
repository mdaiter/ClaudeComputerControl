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
                TextField(placeholder: "search") { query in
                    viewModel.updateSearch(query)
                }
            }
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
                Text(sample.code)
                    .foregroundColor(.white)
            } else if let error = viewModel.generationError {
                Text("Example unavailable: \(error)")
                    .foregroundColor(.red)
            } else {
                Text("Press 'e' to generate an example")
                    .foregroundColor(.gray)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("[up/down] Navigate")
            Text("[/] Search")
            Text("[e] Example")
            Text("[Ctrl+D] Quit")
        }
        .foregroundColor(.gray)
    }

    private func colorForScore(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }
}
