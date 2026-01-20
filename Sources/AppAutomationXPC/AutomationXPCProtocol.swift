import Foundation
import AppAutomationCore

@objc public protocol AppAutomationXPCProtocol {
    func capabilities(with reply: @escaping (Data) -> Void)
    func observe(with reply: @escaping (Data) -> Void)
    func perform(actionData: Data, reply: @escaping (Data) -> Void)
    func startStream(intervalMs: Int, token: String, reply: @escaping (Bool) -> Void)
    func stopStream(token: String, reply: @escaping (Bool) -> Void)
}
