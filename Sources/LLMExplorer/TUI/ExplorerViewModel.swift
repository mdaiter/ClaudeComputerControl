import Combine

final class ExplorerViewModel: ObservableObject {
    let catalog: APICatalog

    @Published var searchQuery: String = ""
    @Published var visibleCount: Int = 30
    @Published var selectedAPI: APIEntry?
    @Published var generatedSample: GeneratedSample?
    @Published var isGeneratingSample: Bool = false
    @Published var generationError: String?

    init(catalog: APICatalog) {
        self.catalog = catalog
    }

    var filteredAPIs: [APIEntry] {
        let apis: [APIEntry]
        if searchQuery.isEmpty {
            apis = Array(catalog.allAPIs.prefix(visibleCount))
        } else {
            apis = catalog.search(query: searchQuery).prefix(visibleCount).map { $0 }
        }
        return apis
    }

    func updateSearch(_ query: String) {
        searchQuery = query
    }

    func selectAPI(_ api: APIEntry?) {
        selectedAPI = api
        if generatedSample?.api.id != api?.id {
            generatedSample = nil
            generationError = nil
            isGeneratingSample = false
        }
    }

    func beginSampleRequest() {
        isGeneratingSample = true
        generationError = nil
    }

    func finishSampleRequest(with sample: GeneratedSample) {
        isGeneratingSample = false
        generationError = nil
        generatedSample = sample
    }

    func failSampleRequest(message: String) {
        isGeneratingSample = false
        generationError = message
    }
}
