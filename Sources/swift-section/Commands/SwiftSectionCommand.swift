import ArgumentParser

private let version = "0.7.0"

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        version: version,
        subcommands: [
            DumpCommand.self,
            InterfaceCommand.self,
            ExploreCommand.self,
        ],
        defaultSubcommand: DumpCommand.self,
    )
}
