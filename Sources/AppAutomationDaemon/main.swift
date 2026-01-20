import Foundation
import AppAutomationCore

let config = DaemonConfig.fromEnvironment()
let streamCoordinator = StreamCoordinator()
let xpcBridge = XPCBridge(config: config)
let router = RequestRouter(dryRun: config.dryRun, streamCoordinator: streamCoordinator, xpcBridge: xpcBridge)
let server = JSONRPCServer(config: config, router: router)
let socketServer = UnixSocketServer(socketPath: config.socketPath)

server.start()

socketServer.start { data in
    Task { @MainActor in
        guard let client = socketServer.currentClient else {
            return
        }
        let writer = JSONRPCMessageWriter(output: client)
        if let tokenValue = server.parseStreamToken(data: data) {
            router.attach(writer: writer, token: AutomationStreamToken(value: tokenValue))
        }
        if let response = server.handle(data) {
            try? writer.sendRaw(response)
        }
    }
}

RunLoop.main.run()
