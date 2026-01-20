import Foundation
import AppAutomationCore

final class JSONRPCServer: @unchecked Sendable {
    private let config: DaemonConfig
    private let router: RequestRouter

    init(config: DaemonConfig, router: RequestRouter) {
        self.config = config
        self.router = router
    }

    func start() {
        print("Starting JSON-RPC server on \(config.socketPath)")
        print("Dry-run: \(config.dryRun ? "enabled" : "disabled")")
    }

    func parseStreamToken(data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(JSONRPCEnvelope.self, from: data) else {
            return nil
        }
        guard envelope.method == "observe_stream.start" else {
            return nil
        }
        return envelope.params?["token"]?.value as? String
    }

    func handle(_ data: Data) -> Data? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(JSONRPCEnvelope.self, from: data) else {
            let response = JSONRPCResponse<AnyCodableValue>(
                id: "unknown",
                result: AutomationResponse(
                    success: false,
                    errorCode: .invalidRequest,
                    message: "Invalid JSON-RPC payload"
                )
            )
            return try? JSONEncoder().encode(response)
        }

        let request = JSONRPCRequest(id: envelope.id, method: envelope.method, params: envelope.params)
        let result = router.route(request: request)
        let response = JSONRPCResponse(id: request.id, result: result)
        return try? JSONEncoder().encode(response)
    }
}
