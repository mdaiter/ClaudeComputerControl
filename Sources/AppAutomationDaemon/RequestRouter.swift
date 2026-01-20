import Foundation
import AppAutomationCore
import AppAutomationAX

final class RequestRouter {
    private let dryRun: Bool
    private let axDriver = AXDriver()
    private let streamCoordinator: StreamCoordinator
    private let xpcBridge: XPCBridge
    private var lastSnapshots: [String: AutomationSnapshot] = [:]

    init(dryRun: Bool, streamCoordinator: StreamCoordinator, xpcBridge: XPCBridge) {
        self.dryRun = dryRun
        self.streamCoordinator = streamCoordinator
        self.xpcBridge = xpcBridge
    }

    func attach(writer: JSONRPCMessageWriter, token: AutomationStreamToken) {
        streamCoordinator.attach(writer: writer, token: token)
    }

    func detachStream(token: AutomationStreamToken) {
        streamCoordinator.detach(token: token)
    }

    func route(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        switch request.method {
        case "health":
            return AutomationResponse(success: true, message: "ok")
        case "list_apps":
            return listApps()
        case "observe":
            return observe(request: request)
        case "diff":
            return diff(request: request)
        case "query":
            return query(request: request)
        case "perform":
            return perform(request: request)
        case "open_url", "menu", "shortcut", "type":
            return delegateAction(request: request)
        case "observe_stream.start", "observe_stream.stop":
            return handleStream(request: request)
        case "capabilities":
            return capabilities(request: request)
        default:
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Unknown method")
        }
    }

    private func listApps() -> AutomationResponse<AnyCodableValue> {
        let apps: [[String: AnyCodableValue]] = [
            [
                "name": AnyCodableValue("Safari"),
                "bundleId": AnyCodableValue("com.apple.Safari"),
                "supported": AnyCodableValue(true)
            ],
            [
                "name": AnyCodableValue("Messages"),
                "bundleId": AnyCodableValue("com.apple.MobileSMS"),
                "supported": AnyCodableValue(true)
            ]
        ]
        return AutomationResponse(success: true, message: "Supported apps", data: AnyCodableValue(apps))
    }

    private func observe(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "App not running")
        }
        let snapshot = axDriver.observe(appName: appName, appElement: appElement, pid: pid)
        lastSnapshots[appName] = snapshot
        return AutomationResponse(success: true, message: "Observed", data: AnyCodableValue(snapshot))
    }

    private func diff(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "App not running")
        }
        let snapshot = axDriver.observe(appName: appName, appElement: appElement, pid: pid)
        let previous = lastSnapshots[appName]
        lastSnapshots[appName] = snapshot
        if let previous {
            let diff = AutomationDiffBuilder.build(previous: previous, current: snapshot)
            return AutomationResponse(success: true, message: diff.summary, data: AnyCodableValue(diff))
        }
        return AutomationResponse(success: true, message: "No previous snapshot", data: AnyCodableValue(snapshot))
    }

    private func query(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let selectorData = request.params?["selector"]?.value as? [String: AnyCodableValue],
              let selector = decodeSelector(from: selectorData) else {
            return AutomationResponse(success: false, errorCode: .invalidSelector, message: "Missing selector")
        }
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "App not running")
        }
        let matches = axDriver.find(appName: appName, appElement: appElement, pid: pid, selector: selector)
        return AutomationResponse(success: true, message: "Query complete", data: AnyCodableValue(matches))
    }

    private func perform(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        if dryRun {
            return AutomationResponse(success: false, errorCode: .dryRunBlocked, message: "Dry-run enabled; actions are blocked")
        }
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let actionData = request.params?["action"]?.value as? [String: AnyCodableValue],
              let action = decodeAction(from: actionData) else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing action")
        }
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "App not running")
        }
        return axDriver.perform(appName: appName, appElement: appElement, pid: pid, action: action)
    }

    private func delegateAction(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        if dryRun {
            return AutomationResponse(success: false, errorCode: .dryRunBlocked, message: "Dry-run enabled; actions are blocked")
        }
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let actionData = request.params?["action"]?.value as? [String: AnyCodableValue],
              var action = decodeAction(from: actionData) else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing action")
        }
        action.action = actionType(for: request.method)
        guard let app = resolveApp(appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "Unsupported app")
        }
        guard let connection = xpcBridge.connection(for: app) else {
            return AutomationResponse(success: false, errorCode: .helperUnavailable, message: "Helper unavailable")
        }
        return withCheckedResponse { completion in
            connection.perform(action: action, completion: completion)
        }
    }

    private func handleStream(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let tokenValue = request.params?["token"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing token")
        }
        let token = AutomationStreamToken(value: tokenValue)
        guard let app = resolveApp(appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "Unsupported app")
        }
        guard let connection = xpcBridge.connection(for: app) else {
            return AutomationResponse(success: false, errorCode: .helperUnavailable, message: "Helper unavailable")
        }
        if request.method == "observe_stream.stop" {
            streamCoordinator.detach(token: token)
            let stopped = withCheckedBool { completion in
                connection.stopStream(token: token, completion: completion)
            }
            return AutomationResponse(success: stopped, message: stopped ? "Stream stopped" : "Stream not running")
        }
        let interval = request.params?["interval_ms"]?.value as? Int ?? 1000
        _ = streamCoordinator.start(token: token, intervalMs: interval) { [weak self] in
            guard let self else { return (nil, nil) }
            guard let snapshot = self.fetchSnapshot(connection: connection) else {
                return (nil, nil)
            }
            let previous = self.lastSnapshots[appName]
            self.lastSnapshots[appName] = snapshot
            if let previous {
                let diff = AutomationDiffBuilder.build(previous: previous, current: snapshot)
                return (snapshot, diff)
            }
            return (snapshot, nil)
        }
        return AutomationResponse(success: true, message: "Stream started")
    }

    private func fetchSnapshot(connection: XPCConnectionWrapper) -> AutomationSnapshot? {
        let semaphore = DispatchSemaphore(value: 0)
        var snapshot: AutomationSnapshot?
        connection.observe { result in
            snapshot = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return snapshot
    }

    private func capabilities(request: JSONRPCRequest) -> AutomationResponse<AnyCodableValue> {
        guard let appName = request.params?["app"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing app name")
        }
        guard let app = resolveApp(appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "Unsupported app")
        }
        guard let connection = xpcBridge.connection(for: app) else {
            return AutomationResponse(success: false, errorCode: .helperUnavailable, message: "Helper unavailable")
        }
        return withCheckedResponse { completion in
            connection.capabilities { profile in
                guard let profile else {
                    completion(nil)
                    return
                }
                completion(AutomationResponse(success: true, message: "Capabilities", data: AnyCodableValue(profile)))
            }
        }
    }

    private func resolveApp(_ appName: String) -> XPCBridge.App? {
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("safari") {
            return .safari
        }
        if normalized.contains("messages") {
            return .messages
        }
        return nil
    }

    private func actionType(for method: String) -> AutomationActionType {
        switch method {
        case "open_url":
            return .openUrl
        case "menu":
            return .menu
        case "shortcut":
            return .shortcut
        case "type":
            return .setValue
        default:
            return .invoke
        }
    }

    private func withCheckedResponse(
        _ execute: (@escaping (AutomationResponse<AnyCodableValue>?) -> Void) -> Void
    ) -> AutomationResponse<AnyCodableValue> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: AutomationResponse<AnyCodableValue>?
        execute {
            result = $0
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return result ?? AutomationResponse(success: false, errorCode: .actionFailed, message: "Helper timeout")
    }

    private func withCheckedBool(_ execute: (@escaping (Bool) -> Void) -> Void) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        execute {
            result = $0
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    private func decodeSelector(from data: [String: AnyCodableValue]) -> AutomationSelector? {
        guard let json = try? JSONEncoder().encode(data.mapValues { $0 }) else {
            return nil
        }
        return try? JSONDecoder().decode(AutomationSelector.self, from: json)
    }

    private func decodeAction(from data: [String: AnyCodableValue]) -> AutomationAction? {
        guard let json = try? JSONEncoder().encode(data.mapValues { $0 }) else {
            return nil
        }
        return try? JSONDecoder().decode(AutomationAction.self, from: json)
    }
}
