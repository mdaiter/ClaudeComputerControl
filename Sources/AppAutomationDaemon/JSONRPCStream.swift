import Foundation
import Dispatch

enum JSONRPCStreamError: Error {
    case invalidHeader
    case missingContentLength
    case unexpectedEOF
}

final class JSONRPCMessageReader {
    private let input: FileHandle
    private var buffer = Data()
    private let chunkSize = 4096
    private let headerTerminator = Data("\r\n\r\n".utf8)

    init(input: FileHandle) {
        self.input = input
    }

    func nextMessage() throws -> Data? {
        while true {
            if let message = try parseBufferedMessage() {
                return message
            }

            guard let chunk = try input.read(upToCount: chunkSize) else {
                if buffer.isEmpty {
                    return nil
                }
                throw JSONRPCStreamError.unexpectedEOF
            }

            if chunk.isEmpty {
                return nil
            }

            buffer.append(chunk)
        }
    }

    private func parseBufferedMessage() throws -> Data? {
        guard let headerRange = buffer.range(of: headerTerminator) else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw JSONRPCStreamError.invalidHeader
        }

        let contentLength = try parseContentLength(from: headerString)
        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }

        let message = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        buffer.removeSubrange(0..<(bodyStart + contentLength))
        return message
    }

    private func parseContentLength(from header: String) throws -> Int {
        var contentLength: Int?
        for line in header.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("content-length:") {
                if let value = trimmed.split(separator: ":").dropFirst().first {
                    contentLength = Int(value.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        guard let contentLength else {
            throw JSONRPCStreamError.missingContentLength
        }

        return contentLength
    }
}

final class JSONRPCMessageWriter {
    private let output: FileHandle
    private let queue = DispatchQueue(label: "app.automation.writer")

    init(output: FileHandle) {
        self.output = output
    }

    func sendRaw(_ bodyData: Data) throws {
        let header = "Content-Length: \(bodyData.count)\r\n\r\n"
        let headerData = Data(header.utf8)

        queue.sync {
            output.write(headerData)
            output.write(bodyData)
        }
    }
}
