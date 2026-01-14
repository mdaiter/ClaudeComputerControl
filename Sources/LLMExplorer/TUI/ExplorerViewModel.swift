import Combine

final class ExplorerViewModel: ObservableObject {
    let catalog: APICatalog

    @Published var searchQuery: String = ""
    @Published var selectedAPI: APIEntry?
    @Published var generatedSample: GeneratedSample?
    @Published var isGeneratingSample: Bool = false
    @Published var generationError: String?
    @Published private var windowStart: Int = 0
    @Published var visibleCount: Int

    init(catalog: APICatalog, visibleCount: Int = 30) {
        self.catalog = catalog
        self.visibleCount = max(visibleCount, 1)
    }

    private var filteredAPIs: [APIEntry] {
        if searchQuery.isEmpty {
            return catalog.allAPIs
        }
        return catalog.search(query: searchQuery)
    }

    var visibleAPIs: [APIEntry] {
        let apis = filteredAPIs
        guard !apis.isEmpty else { return [] }
        let start = clampedWindowStart(for: apis.count)
        let end = min(start + visibleCount, apis.count)
        return Array(apis[start..<end])
    }

    func updateSearch(_ query: String) {
        searchQuery = query
        windowStart = 0
        if let first = filteredAPIs.first {
            selectAPI(first)
        } else {
            selectAPI(nil)
        }
    }

    func selectAPI(_ api: APIEntry?) {
        selectedAPI = api
        if generatedSample?.api.id != api?.id {
            generatedSample = nil
            generationError = nil
            isGeneratingSample = false
        }
        guard let api else { return }
        let apis = filteredAPIs
        guard let index = apis.firstIndex(where: { $0.id == api.id }) else { return }
        ensureSelectionVisible(index: index, totalCount: apis.count)
    }

    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        let apis = filteredAPIs
        guard !apis.isEmpty else { return false }

        var targetIndex: Int
        if let current = selectedAPI, let currentIndex = apis.firstIndex(where: { $0.id == current.id }) {
            targetIndex = currentIndex + offset
        } else {
            targetIndex = offset > 0 ? 0 : apis.count - 1
        }

        targetIndex = max(0, min(targetIndex, apis.count - 1))
        selectAPI(apis[targetIndex])
        return true
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

    private func ensureSelectionVisible(index: Int, totalCount: Int) {
        let maxStart = max(totalCount - visibleCount, 0)
        windowStart = min(max(windowStart, 0), maxStart)

        if index < windowStart {
            windowStart = index
        } else if index >= windowStart + visibleCount {
            windowStart = min(index - visibleCount + 1, maxStart)
        }
    }

    private func clampedWindowStart(for totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        let maxStart = max(totalCount - visibleCount, 0)
        return min(max(windowStart, 0), maxStart)
    }
}
