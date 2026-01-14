import Foundation
import MachOKit
import MachOFoundation
@_spi(Support) import SwiftInterface
@_spi(Support) import LLMExplorer
import ArgumentParser

struct ExploreCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "explore",
        abstract: "Explore Swift APIs in a Mach-O file with LLM assistance."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @Option(name: .shortAndLong, help: "Claude model to use for sample generation.")
    var model: LLMModelOption = .sonnet

    @Option(name: .shortAndLong, help: "Path to export the API catalog JSON.")
    var outputPath: String?

    @Flag(help: "Skip TUI and export catalog directly.")
    var noTUI: Bool = false

    @Flag(help: "Show C-imported types in the analysis.")
    var showCImportedTypes: Bool = false

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)
        let binaryPath = machOOptions.filePath ?? machOOptions.cacheImageName ?? "dyld_shared_cache"

        print("Preparing to analyze Swift interface...")

        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: showCImportedTypes),
            printConfiguration: .init()
        )

        let builder = try SwiftInterfaceBuilder(
            configuration: configuration,
            eventHandlers: [ConsoleEventHandler()],
            in: machOFile
        )

        try await builder.prepare()

        print("Analyzing APIs and computing certainty scores...")

        let analyzer = APICertaintyAnalyzer(machO: machOFile, builder: builder)
        let catalog = try await analyzer.analyze(binaryPath: binaryPath)

        print("Extracted \(catalog.stats.totalAPIs) APIs")
        print("Average certainty: \(String(format: "%.1f", catalog.averageCertainty))")
        print("Distribution: \(catalog.certaintyDistribution.description)")

        // Export if requested
        if let path = outputPath {
            print("Exporting catalog to \(path)...")
            let exporter = ControlLayerExporter()
            try exporter.exportJSON(catalog, to: path)
            print("Export complete.")
        }

        // Run TUI or print summary
        if noTUI {
            if outputPath == nil {
                // Print summary to stdout
                let exporter = ControlLayerExporter()
                print(exporter.exportSummary(catalog, maxAPIs: 50))
            }
        } else {
            print("Starting interactive explorer...")
            print("(Note: TUI requires terminal with curses support)")

            var sampleGenerator: SampleCallGenerator?
            do {
                let client = try ClaudeLLMClient(model: model.model)
                sampleGenerator = SampleCallGenerator(client: client)
            } catch {
                print("LLM sample generation disabled: \(error.localizedDescription)")
            }

            let app = await ExplorerApp(catalog: catalog, sampleGenerator: sampleGenerator)
            await app.run()
        }
    }
}

/// LLM model selection option
enum LLMModelOption: String, ExpressibleByArgument, CaseIterable, Sendable {
    case sonnet = "sonnet"
    case opus = "opus"

    var model: LLMModel {
        switch self {
        case .sonnet: return .claudeSonnet
        case .opus: return .claudeOpus
        }
    }

    static var defaultValueDescription: String { "sonnet" }
}
