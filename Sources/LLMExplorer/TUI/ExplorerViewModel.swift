import Combine

enum ExplorerSearchMode: String {
    case keyword
    case llm

    var displayName: String {
        switch self {
        case .keyword: return "Keyword"
        case .llm: return "LLM"
        }
    }

    var placeholder: String {
        switch self {
        case .keyword: return "search keywords"
        case .llm: return "describe the API you're looking for"
        }
    }
}

final class ExplorerViewModel: ObservableObject {
    let catalog: APICatalog

    @Published var searchQuery: String = ""
    @Published var selectedAPI: APIEntry?
    @Published var generatedSample: GeneratedSample?
    @Published var isGeneratingSample: Bool = false
    @Published var generationError: String?
    @Published var searchMode: ExplorerSearchMode = .keyword
    @Published var isLLMSearching: Bool = false
    @Published var llmSearchError: String?
    @Published private var windowStart: Int = 0
    @Published var isSearchFieldFocused: Bool = false

    private var visibleCount: Int
    private var llmResults: [APIEntry] = []
    private var llmSearchAvailable: Bool = false
    private var llmSearchHandler: ((String) -> Void)?

    init(catalog: APICatalog, visibleCount: Int = 30) {
        self.catalog = catalog
        self.visibleCount = max(visibleCount, 1)
    }

    private var keywordResults: [APIEntry] {
        if searchQuery.isEmpty {
            return catalog.allAPIs
        }
        return catalog.search(query: searchQuery)
    }

    private var currentResults: [APIEntry] {
        switch searchMode {
        case .keyword:
            return keywordResults
        case .llm:
            return llmResults
        }
    }

    var visibleAPIs: [APIEntry] {
        let apis = currentResults
        guard !apis.isEmpty else { return [] }
        let start = clampedWindowStart(for: apis.count)
        let end = min(start + visibleCount, apis.count)
        return Array(apis[start..<end])
    }

    var hasLLMResults: Bool { !llmResults.isEmpty }

    func configureLLMSearch(available: Bool, handler: ((String) -> Void)?) {
        llmSearchAvailable = available
        llmSearchHandler = handler
        if !available && searchMode == .llm {
            searchMode = .keyword
            llmResults = []
            llmSearchError = "LLM search unavailable (set ANTHROPIC_API_KEY)."
        }
    }

    func submitSearch(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch searchMode {
        case .keyword:
            windowStart = 0
            if let first = keywordResults.first {
                selectAPI(first)
            } else {
                selectAPI(nil)
            }
        case .llm:
            guard llmSearchAvailable else {
                llmSearchError = "LLM search unavailable (set ANTHROPIC_API_KEY)."
                return
            }
            guard !searchQuery.isEmpty else {
                llmResults = []
                llmSearchError = "Enter a query before running LLM search."
                isLLMSearching = false
                selectAPI(nil)
                return
            }
            llmResults = []
            llmSearchError = nil
            isLLMSearching = true
            windowStart = 0
            llmSearchHandler?(searchQuery)
        }
    }

    func toggleSearchMode() {
        switch searchMode {
        case .keyword:
            guard llmSearchAvailable else {
                llmSearchError = "LLM search unavailable (set ANTHROPIC_API_KEY)."
                return
            }
            searchMode = .llm
            llmResults = []
            llmSearchError = nil
            selectedAPI = nil
            windowStart = 0
        case .llm:
            searchMode = .keyword
            isLLMSearching = false
            llmSearchError = nil
            llmResults = []
            windowStart = 0
            if let first = keywordResults.first {
                selectAPI(first)
            } else {
                selectAPI(nil)
            }
        }
    }

    func setSearchFieldFocus(_ focused: Bool) {
        isSearchFieldFocused = focused
    }

    func selectAPI(_ api: APIEntry?) {
        selectedAPI = api
        if generatedSample?.api.id != api?.id {
            generatedSample = nil
            generationError = nil
            isGeneratingSample = false
        }
        guard let api else { return }
        let apis = currentResults
        guard let index = apis.firstIndex(where: { $0.id == api.id }) else { return }
        ensureSelectionVisible(index: index, totalCount: apis.count)
    }

    @discardableResult
    func moveSelection(by offset: Int) -> Bool {
        let apis = currentResults
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

    func handleLLMSearchResults(_ results: [APIEntry]) {
        isLLMSearching = false
        windowStart = 0
        llmResults = results
        if let first = results.first {
            selectAPI(first)
        } else {
            selectAPI(nil)
        }
    }

    func handleLLMSearchFailure(_ message: String) {
        isLLMSearching = false
        windowStart = 0
        llmSearchError = message
        llmResults = []
        selectAPI(nil)
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
