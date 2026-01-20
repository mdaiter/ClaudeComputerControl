import Foundation
import Dispatch

final class UnixSocketServer: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "app.automation.socket", qos: .utility)
    private var listener: FileHandle?
    private var client: FileHandle?

    var currentClient: FileHandle? {
        client
    }

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start(onMessage: @escaping @Sendable (Data) -> Void) {
        cleanupSocket()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxLen else {
            print("Socket path too long")
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let buffer = UnsafeMutableRawPointer(ptr).bindMemory(to: UInt8.self, capacity: maxLen)
            buffer.initialize(repeating: 0, count: maxLen)
            buffer.update(from: pathBytes, count: pathBytes.count)
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bindResult == 0 else {
            print("Failed to bind socket")
            close(fd)
            return
        }

        guard listen(fd, 1) == 0 else {
            print("Failed to listen on socket")
            close(fd)
            return
        }

        listener = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

        queue.async {
            self.acceptLoop(onMessage: onMessage)
        }
    }

    private func acceptLoop(onMessage: @escaping (Data) -> Void) {
        guard let listener else { return }
        while true {
            let clientFd = accept(listener.fileDescriptor, nil, nil)
            guard clientFd >= 0 else { continue }
            let handle = FileHandle(fileDescriptor: clientFd, closeOnDealloc: true)
            self.client = handle
            self.readLoop(handle: handle, onMessage: onMessage)
        }
    }

    private func readLoop(handle: FileHandle, onMessage: @escaping (Data) -> Void) {
        let reader = JSONRPCMessageReader(input: handle)
        while true {
            do {
                guard let message = try reader.nextMessage() else { return }
                onMessage(message)
            } catch {
                return
            }
        }
    }

    private func cleanupSocket() {
        let path = socketPath
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
