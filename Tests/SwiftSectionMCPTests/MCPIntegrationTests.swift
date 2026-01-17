import Foundation
import Testing
import XCTest
@testable import SwiftSectionMCPCore

@Suite
struct MCPIntegrationTests {
    @Test
    func swiftInterfaceMatchesCLI() throws {
        guard let env = IntegrationEnvironment.current else {
            throw XCTSkip("Set SWIFT_SECTION_MCP_BINARY, SWIFT_SECTION_CLI_BINARY, and SWIFT_SECTION_FIXTURE to run integration tests.")
        }

        let cliOutput = try env.generateInterfaceWithCLI()
        let harness = try MCPTestHarness(serverPath: env.serverBinary)
        defer { harness.shutdown() }

        let response = try harness.callTool(
            name: "swiftInterface",
            arguments: .object([
                "binaryPath": .string(env.fixturePath),
                "colorScheme": .string("none")
            ])
        )

        let mcpInterface = response.content.compactMap(\.text).last ?? ""
        #expect(cliOutput == mcpInterface)
    }

    @Test
    func listTypesAndSearchSymbolsReturnJSON() throws {
        guard let env = IntegrationEnvironment.current else {
            throw XCTSkip("Set SWIFT_SECTION_MCP_BINARY, SWIFT_SECTION_CLI_BINARY, and SWIFT_SECTION_FIXTURE to run integration tests.")
        }

        let harness = try MCPTestHarness(serverPath: env.serverBinary)
        defer { harness.shutdown() }

        let listResponse = try harness.callTool(
            name: "listTypes",
            arguments: .object([
                "binaryPath": .string(env.fixturePath),
                "limit": .number(10)
            ])
        )

        let listJSON = listResponse.content.compactMap(\.text).last ?? "[]"
        let listRecords = try JSONDecoder().decode([ListTypesRecord].self, from: Data(listJSON.utf8))
        #expect(!listRecords.isEmpty)

        let searchResponse = try harness.callTool(
            name: "searchSymbols",
            arguments: .object([
                "binaryPath": .string(env.fixturePath),
                "query": .string("init"),
                "limit": .number(5)
            ])
        )

        let searchJSON = searchResponse.content.compactMap(\.text).last ?? "[]"
        let searchRecords = try JSONDecoder().decode([SymbolSearchRecord].self, from: Data(searchJSON.utf8))
        #expect(!searchRecords.isEmpty)
    }
}

private struct IntegrationEnvironment {
    let serverBinary: String
    let cliBinary: String
    let fixturePath: String

    static var current: IntegrationEnvironment? {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["SWIFT_SECTION_MCP_BINARY"],
              let cli = env["SWIFT_SECTION_CLI_BINARY"],
              let fixture = env["SWIFT_SECTION_FIXTURE"] else {
            return nil
        }
        return IntegrationEnvironment(serverBinary: server, cliBinary: cli, fixturePath: fixture)
    }

    func generateInterfaceWithCLI() throws -> String {
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swiftinterface")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try run(
            executable: cliBinary,
            arguments: [
                "interface",
                "--color-scheme", "none",
                "--output-path", outputURL.path,
                fixturePath
            ]
        )

        return try String(contentsOf: outputURL, encoding: .utf8)
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationReason != .exit || process.terminationStatus != 0 {
            throw NSError(domain: "SwiftSectionMCP", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Command \(executable) \(arguments.joined(separator: " ")) failed."
            ])
        }
    }
}

