import Foundation
import AppAutomationCore

public protocol AppAutomationServiceProvider {
    var appName: String { get }
    func capabilities() -> CapabilityProfile
    func observe() -> AutomationSnapshot
    func perform(action: AutomationAction) -> AutomationResponse<AnyCodableValue>
    func startStream(intervalMs: Int, token: AutomationStreamToken) -> Bool
    func stopStream(token: AutomationStreamToken) -> Bool
}

public final class AutomationXPCService: NSObject, AppAutomationXPCProtocol {
    private let provider: AppAutomationServiceProvider
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(provider: AppAutomationServiceProvider) {
        self.provider = provider
    }

    public func capabilities(with reply: @escaping (Data) -> Void) {
        let data = (try? encoder.encode(provider.capabilities())) ?? Data()
        reply(data)
    }

    public func observe(with reply: @escaping (Data) -> Void) {
        let data = (try? encoder.encode(provider.observe())) ?? Data()
        reply(data)
    }

    public func perform(actionData: Data, reply: @escaping (Data) -> Void) {
        guard let action = try? decoder.decode(AutomationAction.self, from: actionData) else {
            let response = AutomationResponse<AnyCodableValue>(
                success: false,
                errorCode: .invalidRequest,
                message: "Invalid action payload"
            )
            let data = (try? encoder.encode(response)) ?? Data()
            reply(data)
            return
        }
        let response = provider.perform(action: action)
        let data = (try? encoder.encode(response)) ?? Data()
        reply(data)
    }

    public func startStream(intervalMs: Int, token: String, reply: @escaping (Bool) -> Void) {
        reply(provider.startStream(intervalMs: intervalMs, token: AutomationStreamToken(value: token)))
    }

    public func stopStream(token: String, reply: @escaping (Bool) -> Void) {
        reply(provider.stopStream(token: AutomationStreamToken(value: token)))
    }
}
