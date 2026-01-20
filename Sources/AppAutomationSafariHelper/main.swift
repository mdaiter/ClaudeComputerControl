import Foundation
import AppAutomationCore
import AppAutomationXPC
import AppAutomationAX

final class SafariServiceProvider: NSObject, AppAutomationServiceProvider {
    var appName: String { "Safari" }

    private let axDriver = AXDriver()

    func capabilities() -> CapabilityProfile {
        CapabilityProfile(
            appName: appName,
            pid: 0,
            axScore: 0.5,
            supportsScriptingBridge: true,
            supportsAppleScript: true,
            supportsUrlSchemes: true,
            lastUpdated: ISO8601DateFormatter().string(from: Date())
        )
    }

    func observe() -> AutomationSnapshot {
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationSnapshot(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                appName: appName,
                pid: 0,
                focusedElement: nil,
                elements: [],
                hash: ""
            )
        }
        return axDriver.observe(appName: appName, appElement: appElement, pid: pid)
    }

    func perform(action: AutomationAction) -> AutomationResponse<AnyCodableValue> {
        switch action.action {
        case .openUrl:
            return openUrl(action: action)
        case .invoke:
            return handleInvoke(action: action)
        case .shortcut:
            return sendShortcut(action: action)
        case .menu:
            return executeMenu(action: action)
        default:
            break
        }
        guard let (appElement, pid) = axDriver.connect(appName: appName) else {
            return AutomationResponse(success: false, errorCode: .notConnected, message: "Safari not running")
        }
        return axDriver.perform(appName: appName, appElement: appElement, pid: pid, action: action)
    }
    
    private func executeMenu(action: AutomationAction) -> AutomationResponse<AnyCodableValue> {
        guard let path = action.params?["path"]?.value as? [AnyCodableValue] else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing menu path")
        }
        let menuPath = path.compactMap { $0.value as? String }
        guard menuPath.count >= 2 else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Menu path must have at least 2 items (menu, item)")
        }
        
        let menuName = escapeForAppleScript(menuPath[0])
        let itemPath = menuPath.dropFirst().map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")
        
        let script = """
        tell application "System Events"
            tell process "Safari"
                set frontmost to true
                click menu item {\(itemPath)} of menu "\(menuName)" of menu bar 1
            end tell
        end tell
        """
        return runAppleScript(script)
    }

    func startStream(intervalMs: Int, token: AutomationStreamToken) -> Bool {
        false
    }

    func stopStream(token: AutomationStreamToken) -> Bool {
        false
    }

    private func openUrl(action: AutomationAction) -> AutomationResponse<AnyCodableValue> {
        guard let url = action.params?["url"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing url parameter")
        }
        let escaped = escapeForAppleScript(url)
        let script = "tell application \"Safari\" to open location \"\(escaped)\""
        return runAppleScript(script)
    }

    private func handleInvoke(action: AutomationAction) -> AutomationResponse<AnyCodableValue> {
        guard let command = action.params?["command"]?.value as? String else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing command")
        }
        if command == "tabs" {
            let script = "tell application \"Safari\" to get URL of tabs of windows"
            return runAppleScript(script)
        }
        return AutomationResponse(success: false, errorCode: .unsupportedAction, message: "Unsupported invoke command")
    }

    private func sendShortcut(action: AutomationAction) -> AutomationResponse<AnyCodableValue> {
        guard let keys = action.params?["keys"]?.value as? [AnyCodableValue] else {
            return AutomationResponse(success: false, errorCode: .invalidRequest, message: "Missing keys")
        }
        let keyString = keys.compactMap { $0.value as? String }.joined(separator: ",")
        if keyString.lowercased().contains("new_tab") {
            let script = "tell application \"Safari\" to activate"
            return runAppleScript(script)
        }
        return AutomationResponse(success: false, errorCode: .unsupportedAction, message: "Unsupported shortcut")
    }

    private func runAppleScript(_ script: String) -> AutomationResponse<AnyCodableValue> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return AutomationResponse(success: false, errorCode: .actionFailed, message: "Failed to run AppleScript")
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let response = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            return AutomationResponse(success: false, errorCode: .actionFailed, message: response)
        }
        let payload: AnyCodableValue = response.contains(",")
            ? AnyCodableValue(response.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            : AnyCodableValue(response)
        return AutomationResponse(success: true, message: "OK", data: payload)
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

final class SafariXPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AppAutomationXPCProtocol.self)
        newConnection.exportedObject = AutomationXPCService(provider: SafariServiceProvider())
        newConnection.resume()
        return true
    }
}

let listener = NSXPCListener.service()
let delegate = SafariXPCDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
