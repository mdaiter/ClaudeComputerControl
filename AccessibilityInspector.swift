#!/usr/bin/env swift
// AccessibilityInspector.swift
// Dumps the accessibility hierarchy of any running app
// Usage: swift AccessibilityInspector.swift "App Name"
// Requires: System Preferences → Privacy & Security → Accessibility permission

import ApplicationServices
import AppKit
import Foundation

struct UIElement: Codable {
    let role: String
    let title: String?
    let value: String?
    let actions: [String]
    let children: [UIElement]

    // Flattened summary for LLM context (excludes deep children to save tokens)
    struct Flat: Codable {
        let id: String
        let role: String
        let title: String?
        let value: String?
        let actions: [String]
        let path: String
    }

    func flattened(path: String = "", index: inout Int) -> [Flat] {
        let myId = "e\(index)"
        index += 1
        let currentPath = path.isEmpty ? role : "\(path) > \(role)"

        var result = [Flat(
            id: myId,
            role: role,
            title: title,
            value: value?.count ?? 0 > 100 ? String(value!.prefix(100)) + "..." : value,
            actions: actions,
            path: currentPath
        )]

        for child in children {
            result.append(contentsOf: child.flattened(path: currentPath, index: &index))
        }
        return result
    }
}

struct AppSnapshot: Codable {
    let appName: String
    let bundleIdentifier: String?
    let pid: Int32
    let timestamp: String
    let elements: [UIElement.Flat]
    let summary: Summary

    struct Summary: Codable {
        let totalElements: Int
        let actionableElements: Int
        let textFields: Int
        let buttons: Int
    }
}

func getAttribute(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return result == .success ? value : nil
}

func getStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
    guard let value = getAttribute(element, attr) else { return nil }
    if CFGetTypeID(value) == CFStringGetTypeID() {
        return (value as? String)
    }
    return nil
}

func getActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyActionNames(element, &names)
    guard result == .success, let actionNames = names as? [String] else { return [] }
    return actionNames
}

func inspectElement(_ element: AXUIElement, depth: Int = 0) -> UIElement {
    let role = getStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
    let title = getStringAttribute(element, kAXTitleAttribute)
    let value = getStringAttribute(element, kAXValueAttribute)
    let actions = getActions(element)

    var children: [UIElement] = []
    if let childrenRef = getAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        // Limit depth to avoid infinite recursion
        if depth < 10 {
            children = childrenRef.map { inspectElement($0, depth: depth + 1) }
        }
    }

    return UIElement(role: role, title: title, value: value, actions: actions, children: children)
}

func printElement(_ element: UIElement, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    var desc = "\(pad)[\(element.role)]"

    if let title = element.title, !title.isEmpty {
        desc += " title=\"\(title)\""
    }
    if let value = element.value, !value.isEmpty {
        let truncated = value.count > 50 ? String(value.prefix(50)) + "..." : value
        desc += " value=\"\(truncated)\""
    }
    if !element.actions.isEmpty {
        desc += " actions=[\(element.actions.joined(separator: ", "))]"
    }

    print(desc)

    for child in element.children {
        printElement(child, indent: indent + 1)
    }
}

func generateSwiftStub(_ element: UIElement, appName: String) -> String {
    var stubs: [String] = []

    func collect(_ el: UIElement, path: String) {
        let safePath = path.isEmpty ? "root" : path

        // Generate stub for actionable elements
        if !el.actions.isEmpty {
            let funcName = el.title?.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .prefix(30) ?? "element"

            for action in el.actions where action == "AXPress" {
                stubs.append("""
                    /// \(el.role): \(el.title ?? "untitled")
                    func tap\(funcName.prefix(1).uppercased() + funcName.dropFirst())() {
                        // Path: \(safePath)
                        performAction(role: "\(el.role)", title: \(el.title.map { "\"\($0)\"" } ?? "nil"), action: "AXPress")
                    }
                """)
            }
        }

        // Generate stub for text fields
        if el.role == "AXTextField" || el.role == "AXTextArea" {
            let funcName = el.title?.replacingOccurrences(of: " ", with: "")
                .prefix(30) ?? "textField"
            stubs.append("""
                /// \(el.role): \(el.title ?? "untitled")
                func set\(funcName.prefix(1).uppercased() + funcName.dropFirst())(_ text: String) {
                    // Path: \(safePath)
                    setValue(role: "\(el.role)", title: \(el.title.map { "\"\($0)\"" } ?? "nil"), value: text)
                }
            """)
        }

        for (i, child) in el.children.enumerated() {
            collect(child, path: "\(safePath)/\(child.role)[\(i)]")
        }
    }

    collect(element, path: "")

    return """
    // Auto-generated accessibility stubs for \(appName)
    // Generated: \(Date())

    import ApplicationServices

    class \(appName.replacingOccurrences(of: " ", with: ""))Controller {
        let app: AXUIElement

        init?(appName: String) {
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
                  let pid = app.processIdentifier as pid_t? else { return nil }
            self.app = AXUIElementCreateApplication(pid)
        }

        private func findElement(role: String, title: String?) -> AXUIElement? {
            // Recursive search implementation
            func search(_ element: AXUIElement) -> AXUIElement? {
                var roleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)

                let currentRole = roleValue as? String
                let currentTitle = titleValue as? String

                if currentRole == role && (title == nil || currentTitle == title) {
                    return element
                }

                var children: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
                if let childArray = children as? [AXUIElement] {
                    for child in childArray {
                        if let found = search(child) { return found }
                    }
                }
                return nil
            }
            return search(app)
        }

        private func performAction(role: String, title: String?, action: String) {
            guard let element = findElement(role: role, title: title) else {
                print("Element not found: \\(role) - \\(title ?? "nil")")
                return
            }
            AXUIElementPerformAction(element, action as CFString)
        }

        private func setValue(role: String, title: String?, value: String) {
            guard let element = findElement(role: role, title: title) else {
                print("Element not found: \\(role) - \\(title ?? "nil")")
                return
            }
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        }

        // MARK: - Generated Stubs

    \(stubs.joined(separator: "\n\n"))
    }
    """
}

// MARK: - JSON Export

func createSnapshot(_ hierarchy: UIElement, app: NSRunningApplication) -> AppSnapshot {
    var index = 0
    let flat = hierarchy.flattened(index: &index)

    let summary = AppSnapshot.Summary(
        totalElements: flat.count,
        actionableElements: flat.filter { !$0.actions.isEmpty }.count,
        textFields: flat.filter { $0.role == "AXTextField" || $0.role == "AXTextArea" }.count,
        buttons: flat.filter { $0.role == "AXButton" }.count
    )

    let formatter = ISO8601DateFormatter()
    return AppSnapshot(
        appName: app.localizedName ?? "Unknown",
        bundleIdentifier: app.bundleIdentifier,
        pid: app.processIdentifier,
        timestamp: formatter.string(from: Date()),
        elements: flat,
        summary: summary
    )
}

func exportJSON(_ snapshot: AppSnapshot) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(snapshot),
          let json = String(data: data, encoding: .utf8) else {
        return "{\"error\": \"Failed to encode\"}"
    }
    return json
}

func generateLLMPrompt(_ snapshot: AppSnapshot, task: String?) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let json = (try? encoder.encode(snapshot.elements)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

    let taskDescription = task ?? "Generate a Swift controller class with methods for each actionable element"

    return """
    You are an expert Swift developer. I have an accessibility tree dump from a macOS app called "\(snapshot.appName)".

    ## App Info
    - Name: \(snapshot.appName)
    - Bundle ID: \(snapshot.bundleIdentifier ?? "unknown")
    - Total UI elements: \(snapshot.summary.totalElements)
    - Buttons: \(snapshot.summary.buttons)
    - Text fields: \(snapshot.summary.textFields)
    - Actionable elements: \(snapshot.summary.actionableElements)

    ## Task
    \(taskDescription)

    ## UI Elements (flattened accessibility tree)
    Each element has:
    - id: unique identifier for referencing
    - role: accessibility role (AXButton, AXTextField, etc.)
    - title: visible label
    - value: current value (for text fields, etc.)
    - actions: available actions (AXPress = click, etc.)
    - path: hierarchy path

    ```json
    \(json)
    ```

    ## Requirements
    1. Generate a Swift class using ApplicationServices framework
    2. Use AXUIElement APIs to find and interact with elements
    3. Create typed methods for each actionable element (buttons get tap methods, text fields get set methods)
    4. Include error handling
    5. Make the code production-ready

    Generate the Swift code:
    """
}

// MARK: - Main

guard CommandLine.arguments.count >= 2 else {
    print("""
    Usage: swift AccessibilityInspector.swift <AppName> [options]

    Options:
      --generate-stubs    Generate Swift controller code
      --json              Export as JSON (pipe to file or API)
      --llm               Generate LLM prompt with JSON context
      --llm-task "..."    Custom task for LLM prompt

    Examples:
      swift AccessibilityInspector.swift Safari
      swift AccessibilityInspector.swift Safari --generate-stubs
      swift AccessibilityInspector.swift Safari --json > safari.json
      swift AccessibilityInspector.swift Safari --llm | pbcopy
      swift AccessibilityInspector.swift Spec --llm-task "Create an automation that clicks Run"
    """)
    exit(1)
}

let appName = CommandLine.arguments[1]
let generateStubs = CommandLine.arguments.contains("--generate-stubs")
let exportAsJSON = CommandLine.arguments.contains("--json")
let generateLLM = CommandLine.arguments.contains("--llm") || CommandLine.arguments.contains("--llm-task")
let llmTask: String? = {
    if let idx = CommandLine.arguments.firstIndex(of: "--llm-task"), idx + 1 < CommandLine.arguments.count {
        return CommandLine.arguments[idx + 1]
    }
    return nil
}()

// Check accessibility permission
let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let options = [checkOptPrompt: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(options) else {
    print("❌ Accessibility permission required.")
    print("   Go to: System Preferences → Privacy & Security → Accessibility")
    print("   Add Terminal (or your IDE) to the list.")
    exit(1)
}

// Find the app
guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == appName || $0.bundleIdentifier?.contains(appName.lowercased()) == true
}) else {
    print("❌ App '\(appName)' not found running.")
    print("   Running apps:")
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        print("   - \(app.localizedName ?? "Unknown") (\(app.bundleIdentifier ?? "no bundle id"))")
    }
    exit(1)
}

let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
let hierarchy = inspectElement(appElement)
let snapshot = createSnapshot(hierarchy, app: runningApp)

// Output based on flags
if exportAsJSON {
    // Pure JSON output (no status messages) for piping
    print(exportJSON(snapshot))
} else if generateLLM {
    // LLM prompt output for piping to API
    print(generateLLMPrompt(snapshot, task: llmTask))
} else if generateStubs {
    print("// App: \(runningApp.localizedName ?? appName) (PID: \(runningApp.processIdentifier))")
    print("// Elements: \(snapshot.summary.totalElements) total, \(snapshot.summary.actionableElements) actionable")
    print("")
    print(generateSwiftStub(hierarchy, appName: runningApp.localizedName ?? appName))
} else {
    // Default: human-readable hierarchy
    print("✅ Found: \(runningApp.localizedName ?? appName) (PID: \(runningApp.processIdentifier))")
    print("   Elements: \(snapshot.summary.totalElements) total, \(snapshot.summary.buttons) buttons, \(snapshot.summary.textFields) text fields")
    print("")
    print("UI Hierarchy:")
    print("─────────────")
    printElement(hierarchy)
    print("")
    print("Tips:")
    print("  --generate-stubs  Generate Swift controller code")
    print("  --json            Export as JSON")
    print("  --llm             Generate LLM prompt (pipe to pbcopy or API)")
}
