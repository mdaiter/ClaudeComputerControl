import Foundation
import AppAutomationCore
import AppAutomationXPC

final class XPCConnectionWrapper: @unchecked Sendable {
    private let connection: NSXPCConnection

    init(serviceName: String) {
        connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AppAutomationXPCProtocol.self)
        connection.resume()
    }

    init(machServiceName: String) {
        connection = NSXPCConnection(machServiceName: machServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AppAutomationXPCProtocol.self)
        connection.resume()
    }

    func invalidate() {
        connection.invalidate()
    }

    func capabilities(completion: @escaping (CapabilityProfile?) -> Void) {
        guard let proxy = connection.remoteObjectProxy as? AppAutomationXPCProtocol else {
            completion(nil)
            return
        }
        proxy.capabilities { data in
            completion(try? JSONDecoder().decode(CapabilityProfile.self, from: data))
        }
    }

    func observe(completion: @escaping (AutomationSnapshot?) -> Void) {
        guard let proxy = connection.remoteObjectProxy as? AppAutomationXPCProtocol else {
            completion(nil)
            return
        }
        proxy.observe { data in
            completion(try? JSONDecoder().decode(AutomationSnapshot.self, from: data))
        }
    }

    func perform(action: AutomationAction, completion: @escaping (AutomationResponse<AnyCodableValue>?) -> Void) {
        guard let proxy = connection.remoteObjectProxy as? AppAutomationXPCProtocol else {
            completion(nil)
            return
        }
        guard let data = try? JSONEncoder().encode(action) else {
            completion(nil)
            return
        }
        proxy.perform(actionData: data) { responseData in
            completion(try? JSONDecoder().decode(AutomationResponse<AnyCodableValue>.self, from: responseData))
        }
    }

    func startStream(intervalMs: Int, token: AutomationStreamToken, completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func stopStream(token: AutomationStreamToken, completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}

final class XPCBridge: @unchecked Sendable {
    enum App: String {
        case safari = "Safari"
        case messages = "Messages"
    }

    private let config: DaemonConfig
    private var connections: [App: XPCConnectionWrapper] = [:]
    private var helperTasks: [App: Process] = [:]

    init(config: DaemonConfig) {
        self.config = config
    }

    func connection(for app: App) -> XPCConnectionWrapper? {
        if let existing = connections[app] {
            return existing
        }
        if let task = helperTasks[app], task.isRunning {
            let connection = createConnection(for: app)
            connections[app] = connection
            return connection
        }
        if startHelper(for: app) {
            let connection = createConnection(for: app)
            connections[app] = connection
            return connection
        }
        return nil
    }

    func stopHelpers() {
        for task in helperTasks.values {
            task.terminate()
        }
        for connection in connections.values {
            connection.invalidate()
        }
        helperTasks.removeAll()
        connections.removeAll()
    }

    private func createConnection(for app: App) -> XPCConnectionWrapper {
        XPCConnectionWrapper(machServiceName: serviceName(for: app))
    }

    private func serviceName(for app: App) -> String {
        switch app {
        case .safari:
            return "app.automation.safari"
        case .messages:
            return "app.automation.messages"
        }
    }

    private func startHelper(for app: App) -> Bool {
        guard let helperPath = helperPath(for: app) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = []
        do {
            try process.run()
        } catch {
            return false
        }
        helperTasks[app] = process
        return true
    }

    private func helperPath(for app: App) -> String? {
        switch app {
        case .safari:
            return config.safariHelperPath
        case .messages:
            return config.messagesHelperPath
        }
    }
}
