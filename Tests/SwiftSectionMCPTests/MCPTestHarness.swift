import Foundation
@testable import SwiftSectionMCPCore

final class MCPTestHarness {
    private let process: Process
    private let reader: JSONRPCMessageReader
    private let writer: JSONRPCMessageWriter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var nextID: Int = 1
    private var isRunning = true

    init(serverPath: String) throws {
        process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()

        reader = JSONRPCMessageReader(input: outputPipe.fileHandleForReading)
        writer = JSONRPCMessageWriter(output: inputPipe.fileHandleForWriting)

        try send(method: "initialize", id: .int(nextRequestID()), params: .object([
            "protocolVersion": .string("2024-11-05"),
            "clientInfo": .object([
                "name": .string("SwiftSectionMCPTests")
            ])
        ]))

        _ = try readEnvelope()

        try send(method: "initialized", id: nil, params: nil)
    }

    deinit {
        shutdown()
    }

    func callTool(name: String, arguments: JSONValue) throws -> ToolResponse {
        let params: JSONValue = .object([
            "name": .string(name),
            "arguments": arguments
        ])
        try send(method: "tools/call", id: .int(nextRequestID()), params: params)
        let envelope = try readEnvelope()
        if let error = envelope.error {
            throw NSError(domain: "SwiftSectionMCP", code: error.code, userInfo: [NSLocalizedDescriptionKey: error.message])
        }
        guard let result = envelope.result else {
            throw MCPToolError.encodingFailed
        }
        return try result.decode(ToolResponse.self, using: decoder)
    }

    func shutdown() {
        guard isRunning else { return }
        isRunning = false
        try? send(method: "shutdown", id: .int(nextRequestID()), params: nil)
        _ = try? readEnvelope()
        try? send(method: "exit", id: nil, params: nil)
        process.waitUntilExit()
    }

    private func send(method: String, id: JSONRPCID?, params: JSONValue?) throws {
        struct OutgoingRequest: Encodable {
            let jsonrpc = "2.0"
            let method: String
            let id: JSONRPCID?
            let params: JSONValue?
        }

        let request = OutgoingRequest(method: method, id: id, params: params)
        try writer.send(request, encoder: encoder)
    }

    private func readEnvelope() throws -> JSONRPCResponseEnvelope {
        guard let data = try reader.nextMessage() else {
            throw JSONRPCStreamError.unexpectedEOF
        }
        return try decoder.decode(JSONRPCResponseEnvelope.self, from: data)
    }

    private func nextRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
