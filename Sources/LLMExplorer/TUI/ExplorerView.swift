import SwiftTUI

struct ExplorerView: View {
    let catalog: APICatalog
    @State private var selectedAPI: APIEntry?
    @State private var searchQuery: String = ""
    @State private var visibleCount: Int = 30

    private var filteredAPIs: [APIEntry] {
        guard !searchQuery.isEmpty else {
            return Array(catalog.allAPIs.prefix(visibleCount))
        }
        return catalog.search(query: searchQuery).prefix(visibleCount).map { $0 }
    }

    var body: some View {
        VStack {
            header
            Spacer()
            HStack(alignment: .top) {
                apiList
                if let api = selectedAPI {
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
            Text(catalog.binaryPath)
                .foregroundColor(.cyan)
            HStack {
                Text("\(catalog.stats.typeCount) types")
                Text("\(catalog.stats.protocolCount) protocols")
                Text("\(catalog.stats.functionCount) functions")
                Text("avg: \(Int(catalog.averageCertainty))")
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
                    searchQuery = query
                }
            }
            ForEach(filteredAPIs) { api in
                Button(
                    action: { },
                    hover: { selectedAPI = api }
                ) {
                    HStack {
                        Text("[\(api.certainty.score)]")
                            .foregroundColor(colorForScore(api.certainty.score))
                        Text(api.name)
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
        }
        .padding(.horizontal, 2)
        .frame(minWidth: 30)
        .border()
    }

    private var footer: some View {
        HStack {
            Text("[up/down] Navigate")
            Text("[/] Search")
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
