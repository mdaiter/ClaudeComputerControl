#!/usr/bin/env swift
// AppAgent.swift
// An agentic controller that lets LLMs navigate and control macOS apps
// Uses tool-calling pattern: observe → decide → act → observe changes

import ApplicationServices
import AppKit
import Foundation

// MARK: - Data Models

struct UIElement: Codable {
    let id: String
    let role: String
    let title: String?
    let value: String?
    let actions: [String]
    let enabled: Bool
    let focused: Bool
    let children: [UIElement]

    var isActionable: Bool { !actions.isEmpty && enabled }
    var isTextField: Bool { role == "AXTextField" || role == "AXTextArea" }
    var isButton: Bool { role == "AXButton" }
}

struct UISnapshot: Codable {
    let timestamp: String
    let appName: String
    let pid: Int32
    let focusedElement: String?
    let elements: [FlatElement]
    let hash: String  // For quick diff detection
    let hints: StateHints  // Inferred UI state

    struct FlatElement: Codable, Hashable {
        let id: String
        let role: String
        let subrole: String?
        let title: String?
        let value: String?
        let actions: [String]
        let enabled: Bool
        let path: String
    }

    struct StateHints: Codable {
        let hasModalDialog: Bool
        let hasErrorIndicator: Bool
        let hasLoadingIndicator: Bool
        let hasTextField: Bool
        let hasEnabledButtons: Bool
        let visibleText: [String]  // Key text content for LLM context
        let inferredState: String  // "login_form", "loading", "error_dialog", "content_view", etc.
    }
}

struct UIDiff: Codable {
    let changed: Bool
    let added: [UISnapshot.FlatElement]
    let removed: [UISnapshot.FlatElement]
    let modified: [ElementChange]
    let signals: [String]  // Extracted observations about what changed
    let summary: String

    struct ElementChange: Codable {
        let id: String
        let field: String
        let before: String?
        let after: String?
    }
}

struct ToolResult: Codable {
    let success: Bool
    let message: String
    let data: AnyCodable?
}

// Helper for encoding arbitrary data
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr }
        else { value = "null" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case let snapshot as UISnapshot:
            try container.encode(snapshot)
        case let diff as UIDiff:
            try container.encode(diff)
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Navigation Scratch Pad (Mental Model)

struct NavigationContext: Codable {
    var currentPath: [PathElement]      // Where am I? (breadcrumb trail)
    var landmarks: [Landmark]           // Known orientation points
    var visitedAreas: Set<String>       // What have I explored?
    var workingMemory: [MemoryItem]     // Recent observations/actions
    var hypothesis: String?             // Current belief about app state

    struct PathElement: Codable, Hashable {
        let id: String
        let role: String
        let title: String?
    }

    struct Landmark: Codable, Hashable {
        let id: String
        let role: String
        let title: String?
        let landmarkType: String  // "toolbar", "sidebar", "main", "navigation", "search", "form"
    }

    struct MemoryItem: Codable {
        let timestamp: String
        let action: String
        let observation: String
    }

    static func empty() -> NavigationContext {
        NavigationContext(
            currentPath: [],
            landmarks: [],
            visitedAreas: [],
            workingMemory: [],
            hypothesis: nil
        )
    }

    mutating func addMemory(_ action: String, _ observation: String) {
        let item = MemoryItem(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            action: action,
            observation: observation
        )
        workingMemory.append(item)
        // Keep last 20 items (sliding window)
        if workingMemory.count > 20 {
            workingMemory.removeFirst()
        }
    }

    mutating func updatePath(_ element: UISnapshot.FlatElement) {
        // Parse path string into breadcrumbs
        let components = element.path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        currentPath = components.enumerated().map { (i, role) in
            PathElement(id: "path_\(i)", role: String(role), title: nil)
        }
    }

    func summarize() -> String {
        var parts: [String] = []

        if !currentPath.isEmpty {
            let pathStr = currentPath.map { $0.title ?? $0.role }.joined(separator: " → ")
            parts.append("Location: \(pathStr)")
        }

        if !landmarks.isEmpty {
            let landmarkStr = landmarks.prefix(5).map { "\($0.landmarkType): \($0.title ?? $0.role)" }.joined(separator: ", ")
            parts.append("Landmarks: \(landmarkStr)")
        }

        if let hyp = hypothesis {
            parts.append("Hypothesis: \(hyp)")
        }

        if !workingMemory.isEmpty {
            let recent = workingMemory.suffix(3).map { "[\($0.action)] \($0.observation)" }.joined(separator: "; ")
            parts.append("Recent: \(recent)")
        }

        return parts.isEmpty ? "No navigation context yet" : parts.joined(separator: "\n")
    }
}

// MARK: - Agent Controller

class AppAgent {
    let appName: String
    var app: AXUIElement?
    var pid: pid_t = 0
    var lastSnapshot: UISnapshot?
    var elementCache: [String: AXUIElement] = [:]
    var navContext: NavigationContext = .empty()  // The "scratch pad"
    var focusedElementId: String?  // Currently focused element for incremental nav

    init(appName: String) {
        self.appName = appName
    }

    func connect() -> ToolResult {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == appName ||
            $0.bundleIdentifier?.localizedCaseInsensitiveContains(appName) == true
        }) else {
            return ToolResult(success: false, message: "App '\(appName)' not found running", data: nil)
        }

        self.pid = runningApp.processIdentifier
        self.app = AXUIElementCreateApplication(pid)
        return ToolResult(success: true, message: "Connected to \(runningApp.localizedName ?? appName) (PID: \(pid))", data: nil)
    }

    // MARK: - Tools

    func observeUI() -> ToolResult {
        guard let app = app else {
            return ToolResult(success: false, message: "Not connected to app", data: nil)
        }

        elementCache.removeAll()
        var index = 0
        let root = inspectElement(app, id: &index, path: "")
        let flat = flatten(root)
        let hints = computeHints(flat)

        let snapshot = UISnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            appName: appName,
            pid: pid,
            focusedElement: findFocusedElementId(),
            elements: flat,
            hash: String(flat.map { "\($0.id):\($0.title ?? ""):\($0.value ?? "")" }.joined().hashValue),
            hints: hints
        )

        lastSnapshot = snapshot

        // Include hints in message for quick LLM understanding
        let msg = "Observed \(flat.count) elements. State: \(hints.inferredState)" +
                  (hints.hasErrorIndicator ? " [ERROR DETECTED]" : "") +
                  (hints.hasLoadingIndicator ? " [LOADING]" : "") +
                  (hints.hasModalDialog ? " [MODAL OPEN]" : "")

        return ToolResult(success: true, message: msg, data: AnyCodable(snapshot))
    }

    func diffUI() -> ToolResult {
        guard let previous = lastSnapshot else {
            return ToolResult(success: false, message: "No previous snapshot to diff against. Call observe_ui first.", data: nil)
        }

        let currentResult = observeUI()
        guard currentResult.success, let current = lastSnapshot else {
            return currentResult
        }

        let prevSet = Set(previous.elements)
        let currSet = Set(current.elements)

        let added = currSet.subtracting(prevSet)
        let removed = prevSet.subtracting(currSet)

        // Find modified (same id, different content)
        var modified: [UIDiff.ElementChange] = []
        let prevById = Dictionary(uniqueKeysWithValues: previous.elements.map { ($0.id, $0) })
        let currById = Dictionary(uniqueKeysWithValues: current.elements.map { ($0.id, $0) })

        for (id, curr) in currById {
            if let prev = prevById[id] {
                if prev.value != curr.value {
                    modified.append(UIDiff.ElementChange(id: id, field: "value", before: prev.value, after: curr.value))
                }
                if prev.title != curr.title {
                    modified.append(UIDiff.ElementChange(id: id, field: "title", before: prev.title, after: curr.title))
                }
                if prev.enabled != curr.enabled {
                    modified.append(UIDiff.ElementChange(id: id, field: "enabled", before: String(prev.enabled), after: String(curr.enabled)))
                }
            }
        }

        let changed = !added.isEmpty || !removed.isEmpty || !modified.isEmpty

        // Extract signals from actual changes (not abstract state machine)
        let signals = extractChangeSignals(
            added: added,
            removed: removed,
            modified: modified,
            prevHints: previous.hints,
            currHints: current.hints
        )

        // Build summary
        var summaryParts: [String] = []
        if !added.isEmpty { summaryParts.append("\(added.count) added") }
        if !removed.isEmpty { summaryParts.append("\(removed.count) removed") }
        if !modified.isEmpty { summaryParts.append("\(modified.count) modified") }

        var summary = changed ? "UI changed: \(summaryParts.joined(separator: ", ")). " : "No changes detected. "
        if !signals.isEmpty {
            summary += "Signals: \(signals.joined(separator: "; "))"
        }

        let diff = UIDiff(
            changed: changed,
            added: Array(added),
            removed: Array(removed),
            modified: modified,
            signals: signals,
            summary: summary
        )

        return ToolResult(success: true, message: summary, data: AnyCodable(diff))
    }

    /// Extract meaningful signals from what actually changed, not from abstract states
    private func extractChangeSignals(
        added: Set<UISnapshot.FlatElement>,
        removed: Set<UISnapshot.FlatElement>,
        modified: [UIDiff.ElementChange],
        prevHints: UISnapshot.StateHints,
        currHints: UISnapshot.StateHints
    ) -> [String] {
        var signals: [String] = []

        // Analyze what was removed
        let removedTitles = removed.compactMap { $0.title?.lowercased() }
        let removedRoles = Set(removed.map { $0.role })

        if removedRoles.contains("AXSheet") || removedRoles.contains("AXDialog") {
            signals.append("modal/dialog closed")
        }
        if removedTitles.contains(where: { $0.contains("login") || $0.contains("sign in") }) {
            signals.append("login UI no longer visible")
        }
        if removed.contains(where: { $0.role == "AXProgressIndicator" }) {
            signals.append("progress indicator gone")
        }

        // Analyze what was added
        let addedTitles = added.compactMap { $0.title?.lowercased() }
        let addedValues = added.compactMap { $0.value?.lowercased() }
        let addedText = addedTitles + addedValues
        let addedRoles = Set(added.map { $0.role })

        if addedRoles.contains("AXSheet") || addedRoles.contains("AXDialog") {
            signals.append("new modal/dialog appeared")
        }
        if addedRoles.contains("AXProgressIndicator") || addedRoles.contains("AXBusyIndicator") {
            signals.append("loading indicator appeared")
        }

        // Check for sentiment in new text
        let positiveWords = ["success", "welcome", "complete", "done", "saved", "created", "thank"]
        let negativeWords = ["error", "failed", "invalid", "denied", "unable", "couldn't", "wrong", "incorrect"]
        let actionWords = ["confirm", "are you sure", "delete", "remove", "cancel", "continue"]

        if addedText.contains(where: { text in positiveWords.contains(where: { text.contains($0) }) }) {
            signals.append("positive feedback text appeared")
        }
        if addedText.contains(where: { text in negativeWords.contains(where: { text.contains($0) }) }) {
            signals.append("error/negative text appeared")
        }
        if addedText.contains(where: { text in actionWords.contains(where: { text.contains($0) }) }) {
            signals.append("confirmation prompt appeared")
        }

        // Analyze capability changes
        let addedButtons = added.filter { $0.role == "AXButton" && $0.enabled }
        let removedButtons = removed.filter { $0.role == "AXButton" }
        let addedTextFields = added.filter { $0.role == "AXTextField" || $0.role == "AXTextArea" }
        let removedTextFields = removed.filter { $0.role == "AXTextField" || $0.role == "AXTextArea" }

        if addedButtons.count > removedButtons.count + 2 {
            signals.append("more interactive options now available")
        }
        if removedButtons.count > addedButtons.count + 2 {
            signals.append("fewer interactive options than before")
        }
        if !addedTextFields.isEmpty && removedTextFields.isEmpty {
            signals.append("new input field(s) appeared")
        }
        if !removedTextFields.isEmpty && addedTextFields.isEmpty {
            signals.append("input field(s) gone - possibly submitted")
        }

        // Check for navigation patterns
        let addedWindows = added.filter { $0.role == "AXWindow" }
        let removedWindows = removed.filter { $0.role == "AXWindow" }
        if !addedWindows.isEmpty {
            let titles = addedWindows.compactMap { $0.title }.joined(separator: ", ")
            signals.append("new window: \(titles.isEmpty ? "(untitled)" : titles)")
        }
        if !removedWindows.isEmpty {
            signals.append("window closed")
        }

        // Value changes often indicate data updates
        let valueChanges = modified.filter { $0.field == "value" }
        if valueChanges.count > 3 {
            signals.append("\(valueChanges.count) values changed - content updated")
        }

        // Enabled/disabled changes indicate state progression
        let enabledChanges = modified.filter { $0.field == "enabled" }
        let newlyEnabled = enabledChanges.filter { $0.after == "true" }.count
        let newlyDisabled = enabledChanges.filter { $0.after == "false" }.count
        if newlyEnabled > newlyDisabled {
            signals.append("more controls became enabled")
        } else if newlyDisabled > newlyEnabled {
            signals.append("some controls became disabled")
        }

        // If nothing specific detected but things changed
        if signals.isEmpty && (!added.isEmpty || !removed.isEmpty || !modified.isEmpty) {
            let magnitude = added.count + removed.count + modified.count
            if magnitude > 20 {
                signals.append("major UI restructure (\(magnitude) changes)")
            } else if magnitude > 5 {
                signals.append("moderate UI update (\(magnitude) changes)")
            } else {
                signals.append("minor UI change")
            }
        }

        return signals
    }

    func click(elementId: String) -> ToolResult {
        guard let element = elementCache[elementId] else {
            return ToolResult(success: false, message: "Element '\(elementId)' not found. Call observe_ui first to refresh.", data: nil)
        }

        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result == .success {
            return ToolResult(success: true, message: "Clicked element \(elementId)", data: nil)
        } else {
            return ToolResult(success: false, message: "Failed to click: AXError \(result.rawValue)", data: nil)
        }
    }

    func type(elementId: String, text: String) -> ToolResult {
        guard let element = elementCache[elementId] else {
            return ToolResult(success: false, message: "Element '\(elementId)' not found", data: nil)
        }

        // First focus the element
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)

        // Then set the value
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        if result == .success {
            return ToolResult(success: true, message: "Typed '\(text)' into \(elementId)", data: nil)
        } else {
            return ToolResult(success: false, message: "Failed to type: AXError \(result.rawValue)", data: nil)
        }
    }

    func focus(elementId: String) -> ToolResult {
        guard let element = elementCache[elementId] else {
            return ToolResult(success: false, message: "Element '\(elementId)' not found", data: nil)
        }

        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        if result == .success {
            return ToolResult(success: true, message: "Focused element \(elementId)", data: nil)
        } else {
            return ToolResult(success: false, message: "Failed to focus: AXError \(result.rawValue)", data: nil)
        }
    }

    func pressKey(key: String, modifiers: [String] = []) -> ToolResult {
        // Map key names to key codes
        let keyCodes: [String: CGKeyCode] = [
            "return": 0x24, "enter": 0x24,
            "tab": 0x30,
            "space": 0x31,
            "escape": 0x35, "esc": 0x35,
            "delete": 0x33, "backspace": 0x33,
            "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
        ]

        guard let keyCode = keyCodes[key.lowercased()] else {
            return ToolResult(success: false, message: "Unknown key: \(key)", data: nil)
        }

        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = flags
        keyUp?.flags = flags

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        let modStr = modifiers.isEmpty ? "" : "(\(modifiers.joined(separator: "+"))) "
        return ToolResult(success: true, message: "Pressed \(modStr)\(key)", data: nil)
    }

    func wait(seconds: Double) -> ToolResult {
        Thread.sleep(forTimeInterval: seconds)
        return ToolResult(success: true, message: "Waited \(seconds)s", data: nil)
    }

    func listActions(elementId: String) -> ToolResult {
        guard let element = elementCache[elementId] else {
            return ToolResult(success: false, message: "Element '\(elementId)' not found", data: nil)
        }

        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        let actions = (names as? [String]) ?? []

        return ToolResult(success: true, message: "Actions for \(elementId): \(actions.joined(separator: ", "))", data: AnyCodable(actions))
    }

    // MARK: - VoiceOver-Style Navigation

    /// "Where am I?" - Describe current position and context
    func whereAmI() -> ToolResult {
        let summary = navContext.summarize()

        // Also describe the currently focused element if any
        var focusDesc = "No element focused"
        if let focusId = focusedElementId,
           let element = lastSnapshot?.elements.first(where: { $0.id == focusId }) {
            focusDesc = describeElement(element)
        }

        let response = """
        \(summary)

        Focused: \(focusDesc)
        """

        return ToolResult(success: true, message: response, data: AnyCodable(navContext))
    }

    /// Move to next/previous sibling element
    func navigate(direction: String) -> ToolResult {
        guard let snapshot = lastSnapshot else {
            return ToolResult(success: false, message: "No UI observed yet. Call observe_ui first.", data: nil)
        }

        let elements = snapshot.elements.filter { $0.enabled }
        guard !elements.isEmpty else {
            return ToolResult(success: false, message: "No navigable elements", data: nil)
        }

        let currentIndex = focusedElementId.flatMap { id in elements.firstIndex(where: { $0.id == id }) } ?? -1

        let newIndex: Int
        switch direction.lowercased() {
        case "next", "forward":
            newIndex = min(currentIndex + 1, elements.count - 1)
        case "prev", "previous", "back":
            newIndex = max(currentIndex - 1, 0)
        case "first":
            newIndex = 0
        case "last":
            newIndex = elements.count - 1
        default:
            return ToolResult(success: false, message: "Direction must be: next, prev, first, last", data: nil)
        }

        let element = elements[newIndex]
        focusedElementId = element.id
        navContext.updatePath(element)
        navContext.addMemory("navigate \(direction)", describeElement(element))

        return ToolResult(
            success: true,
            message: "[\(newIndex + 1)/\(elements.count)] \(describeElement(element))",
            data: AnyCodable(element)
        )
    }

    /// Jump to next element matching a role (like VO+Cmd+H for headings)
    func jumpTo(role: String, direction: String = "next") -> ToolResult {
        guard let snapshot = lastSnapshot else {
            return ToolResult(success: false, message: "No UI observed yet", data: nil)
        }

        let targetRole = "AX\(role.replacingOccurrences(of: "AX", with: ""))"
        let matching = snapshot.elements.filter {
            $0.role.lowercased() == targetRole.lowercased() && $0.enabled
        }

        guard !matching.isEmpty else {
            return ToolResult(success: false, message: "No elements with role '\(role)' found", data: nil)
        }

        let currentIndex = focusedElementId.flatMap { id in matching.firstIndex(where: { $0.id == id }) } ?? -1

        let newIndex: Int
        if direction == "prev" {
            newIndex = currentIndex > 0 ? currentIndex - 1 : matching.count - 1
        } else {
            newIndex = currentIndex < matching.count - 1 ? currentIndex + 1 : 0
        }

        let element = matching[newIndex]
        focusedElementId = element.id
        navContext.updatePath(element)
        navContext.addMemory("jump to \(role)", describeElement(element))

        return ToolResult(
            success: true,
            message: "[\(newIndex + 1)/\(matching.count) \(role)s] \(describeElement(element))",
            data: AnyCodable(element)
        )
    }

    /// List all landmarks (like VO rotor for landmarks)
    func listLandmarks() -> ToolResult {
        guard let snapshot = lastSnapshot else {
            return ToolResult(success: false, message: "No UI observed yet", data: nil)
        }

        // Detect landmarks from the UI
        var landmarks: [NavigationContext.Landmark] = []

        for element in snapshot.elements {
            let landmarkType = detectLandmarkType(element)
            if let type = landmarkType {
                landmarks.append(NavigationContext.Landmark(
                    id: element.id,
                    role: element.role,
                    title: element.title,
                    landmarkType: type
                ))
            }
        }

        // Update nav context
        navContext.landmarks = landmarks

        if landmarks.isEmpty {
            return ToolResult(success: true, message: "No landmarks detected", data: nil)
        }

        let desc = landmarks.enumerated().map { (i, lm) in
            "[\(i + 1)] \(lm.landmarkType): \(lm.title ?? lm.role) (\(lm.id))"
        }.joined(separator: "\n")

        return ToolResult(
            success: true,
            message: "Found \(landmarks.count) landmarks:\n\(desc)",
            data: AnyCodable(landmarks)
        )
    }

    /// Jump to a specific landmark by index or type
    func goToLandmark(identifier: String) -> ToolResult {
        if navContext.landmarks.isEmpty {
            _ = listLandmarks()  // Auto-detect if not done
        }

        var target: NavigationContext.Landmark?

        // Try as index first
        if let index = Int(identifier), index > 0, index <= navContext.landmarks.count {
            target = navContext.landmarks[index - 1]
        } else {
            // Try as type
            target = navContext.landmarks.first { $0.landmarkType.lowercased() == identifier.lowercased() }
        }

        guard let landmark = target else {
            return ToolResult(success: false, message: "Landmark '\(identifier)' not found", data: nil)
        }

        focusedElementId = landmark.id
        if let element = lastSnapshot?.elements.first(where: { $0.id == landmark.id }) {
            navContext.updatePath(element)
        }
        navContext.addMemory("go to landmark", "\(landmark.landmarkType): \(landmark.title ?? landmark.role)")

        return ToolResult(
            success: true,
            message: "Jumped to \(landmark.landmarkType): \(landmark.title ?? landmark.role)",
            data: AnyCodable(landmark)
        )
    }

    /// Describe current element in detail (like VO+F3)
    func describeCurrent() -> ToolResult {
        guard let focusId = focusedElementId,
              let element = lastSnapshot?.elements.first(where: { $0.id == focusId }) else {
            return ToolResult(success: false, message: "No element focused. Use navigate() first.", data: nil)
        }

        let desc = describeElementVerbose(element)
        return ToolResult(success: true, message: desc, data: AnyCodable(element))
    }

    /// Set a hypothesis about current state (LLM's belief)
    func setHypothesis(_ hypothesis: String) -> ToolResult {
        navContext.hypothesis = hypothesis
        navContext.addMemory("hypothesis", hypothesis)
        return ToolResult(success: true, message: "Hypothesis recorded: \(hypothesis)", data: nil)
    }

    /// Find elements that have actual text content (title or value)
    func findContent(query: String? = nil, count: Int = 20) -> ToolResult {
        guard let snapshot = lastSnapshot else {
            return ToolResult(success: false, message: "No UI observed yet", data: nil)
        }

        // Find elements with text content
        var withContent = snapshot.elements.filter { el in
            let hasContent = (el.title != nil && !el.title!.isEmpty) ||
                             (el.value != nil && !el.value!.isEmpty)
            if let q = query?.lowercased(), !q.isEmpty {
                let text = (el.title ?? "") + (el.value ?? "")
                return hasContent && text.lowercased().contains(q)
            }
            return hasContent
        }

        // Sort by likely importance (buttons/cells with content first)
        withContent.sort { a, b in
            let aScore = (a.role == "AXButton" || a.role == "AXCell") ? 1 : 0
            let bScore = (b.role == "AXButton" || b.role == "AXCell") ? 1 : 0
            return aScore > bScore
        }

        let results = Array(withContent.prefix(count))

        if results.isEmpty {
            return ToolResult(success: true, message: "No elements with text content found" + (query != nil ? " matching '\(query!)'" : ""), data: nil)
        }

        let desc = results.map { el in
            let content = el.title ?? el.value ?? ""
            let truncated = content.count > 70 ? String(content.prefix(70)) + "..." : content
            let actions = el.actions.isEmpty ? "" : " [clickable]"
            return "[\(el.id)] \(el.role.replacingOccurrences(of: "AX", with: ""))\(actions): \(truncated)"
        }.joined(separator: "\n")

        return ToolResult(
            success: true,
            message: "Found \(results.count) elements with content:\n\(desc)",
            data: AnyCodable(results)
        )
    }

    /// Get a summary of nearby actionable elements (like VO item chooser)
    func listNearby(count: Int = 10) -> ToolResult {
        guard let snapshot = lastSnapshot else {
            return ToolResult(success: false, message: "No UI observed yet", data: nil)
        }

        let actionable = snapshot.elements.filter { !$0.actions.isEmpty && $0.enabled }
        let currentIndex = focusedElementId.flatMap { id in actionable.firstIndex(where: { $0.id == id }) } ?? 0

        // Get elements around current position
        let start = max(0, currentIndex - count / 2)
        let end = min(actionable.count, start + count)
        let nearby = Array(actionable[start..<end])

        let desc = nearby.enumerated().map { (i, el) in
            let marker = el.id == focusedElementId ? "→" : " "
            let label = el.title ?? el.value ?? "(no label)"
            let truncated = label.count > 60 ? String(label.prefix(60)) + "..." : label
            return "\(marker) [\(el.id)] \(el.role.replacingOccurrences(of: "AX", with: "")): \(truncated)"
        }.joined(separator: "\n")

        return ToolResult(
            success: true,
            message: "Nearby actionable elements (\(nearby.count) of \(actionable.count)):\n\(desc)",
            data: AnyCodable(nearby)
        )
    }

    // MARK: - Navigation Helpers

    private func describeElement(_ element: UISnapshot.FlatElement) -> String {
        var parts: [String] = [element.role.replacingOccurrences(of: "AX", with: "")]

        // Show title or value (whichever is available)
        if let title = element.title, !title.isEmpty {
            let truncated = title.count > 50 ? String(title.prefix(50)) + "..." : title
            parts.append("\"\(truncated)\"")
        } else if let value = element.value, !value.isEmpty {
            let truncated = value.count > 50 ? String(value.prefix(50)) + "..." : value
            parts.append("\"\(truncated)\"")
        }

        if !element.enabled {
            parts.append("(disabled)")
        }
        if !element.actions.isEmpty {
            let actionStr = element.actions.map { $0.replacingOccurrences(of: "AX", with: "") }.prefix(3).joined(separator: ", ")
            parts.append("[\(actionStr)]")
        }

        return parts.joined(separator: " ")
    }

    private func describeElementVerbose(_ element: UISnapshot.FlatElement) -> String {
        return """
        Element: \(element.id)
        Role: \(element.role)
        Title: \(element.title ?? "(none)")
        Value: \(element.value ?? "(none)")
        Enabled: \(element.enabled)
        Actions: \(element.actions.isEmpty ? "none" : element.actions.joined(separator: ", "))
        Path: \(element.path)
        """
    }

    private func detectLandmarkType(_ element: UISnapshot.FlatElement) -> String? {
        let role = element.role.lowercased()
        let title = element.title?.lowercased() ?? ""

        // Standard accessibility roles
        if role.contains("toolbar") { return "toolbar" }
        if role.contains("sidebar") || title.contains("sidebar") { return "sidebar" }
        if role.contains("navigation") || role.contains("navbar") { return "navigation" }
        if role.contains("search") || title.contains("search") { return "search" }
        if role.contains("main") || role.contains("content") { return "main" }

        // Common UI patterns
        if role == "axsplitgroup" { return "split-view" }
        if role == "axtabgroup" { return "tabs" }
        if role == "axoutline" || role == "axtable" { return "list" }
        if role == "axscrollarea" && element.path.contains("AXWindow") && !element.path.contains("AXSheet") {
            // Top-level scroll area is likely main content
            if element.title != nil { return "main" }
        }

        // Form detection
        let hasInputs = title.contains("form") || title.contains("login") || title.contains("sign")
        if hasInputs { return "form" }

        return nil
    }

    // MARK: - Helpers

    private func inspectElement(_ element: AXUIElement, id: inout Int, path: String) -> UIElement {
        let myId = "e\(id)"
        id += 1
        elementCache[myId] = element

        let role = getStringAttr(element, kAXRoleAttribute) ?? "Unknown"
        let title = getStringAttr(element, kAXTitleAttribute)
        var value = getStringAttr(element, kAXValueAttribute)
        if let v = value, v.count > 200 { value = String(v.prefix(200)) + "..." }

        let enabled = getBoolAttr(element, kAXEnabledAttribute) ?? true
        let focused = getBoolAttr(element, kAXFocusedAttribute) ?? false

        var actions: [String] = []
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success {
            actions = (actionNames as? [String]) ?? []
        }

        var children: [UIElement] = []
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let childArray = childrenRef as? [AXUIElement] {
            let newPath = path.isEmpty ? role : "\(path) > \(role)"
            children = childArray.prefix(100).map { inspectElement($0, id: &id, path: newPath) }
        }

        return UIElement(id: myId, role: role, title: title, value: value, actions: actions, enabled: enabled, focused: focused, children: children)
    }

    private func flatten(_ element: UIElement, path: String = "") -> [UISnapshot.FlatElement] {
        let currentPath = path.isEmpty ? element.role : "\(path) > \(element.role)"
        var result = [UISnapshot.FlatElement(
            id: element.id,
            role: element.role,
            subrole: nil,  // Could be populated if we read AXSubrole
            title: element.title,
            value: element.value,
            actions: element.actions,
            enabled: element.enabled,
            path: currentPath
        )]
        for child in element.children {
            result.append(contentsOf: flatten(child, path: currentPath))
        }
        return result
    }

    private func computeHints(_ elements: [UISnapshot.FlatElement]) -> UISnapshot.StateHints {
        let roles = Set(elements.map { $0.role })
        let allText = elements.compactMap { $0.title } + elements.compactMap { $0.value }
        let lowerText = allText.map { $0.lowercased() }

        // Detect modal dialogs
        let hasModal = roles.contains("AXSheet") || roles.contains("AXDialog") ||
                       elements.contains { $0.role == "AXWindow" && $0.path.contains("AXSheet") }

        // Detect error indicators
        let errorKeywords = ["error", "failed", "invalid", "incorrect", "denied", "couldn't", "unable"]
        let hasError = lowerText.contains { text in errorKeywords.contains { text.contains($0) } }

        // Detect loading indicators
        let loadingKeywords = ["loading", "processing", "please wait", "saving", "connecting"]
        let hasLoading = lowerText.contains { text in loadingKeywords.contains { text.contains($0) } } ||
                         roles.contains("AXProgressIndicator") || roles.contains("AXBusyIndicator")

        // Basic capabilities
        let hasTextField = elements.contains { $0.role == "AXTextField" || $0.role == "AXTextArea" }
        let hasEnabledButtons = elements.contains { $0.role == "AXButton" && $0.enabled }

        // Extract key visible text (for LLM context, limit to important stuff)
        let keyText = allText
            .filter { $0.count > 2 && $0.count < 100 }  // Skip tiny or huge text
            .filter { !$0.allSatisfy { $0.isWhitespace } }
            .prefix(20)
            .map { String($0) }

        // Infer high-level state
        let inferredState: String
        if hasError && hasModal {
            inferredState = "error_dialog"
        } else if hasError {
            inferredState = "error_state"
        } else if hasLoading {
            inferredState = "loading"
        } else if hasModal {
            inferredState = "modal_dialog"
        } else if hasTextField && hasEnabledButtons {
            // Check for common form patterns
            let formKeywords = ["login", "sign in", "password", "email", "username", "search"]
            if lowerText.contains(where: { text in formKeywords.contains { text.contains($0) } }) {
                inferredState = "form_input"
            } else {
                inferredState = "interactive_content"
            }
        } else if hasEnabledButtons {
            inferredState = "interactive_content"
        } else {
            inferredState = "static_content"
        }

        return UISnapshot.StateHints(
            hasModalDialog: hasModal,
            hasErrorIndicator: hasError,
            hasLoadingIndicator: hasLoading,
            hasTextField: hasTextField,
            hasEnabledButtons: hasEnabledButtons,
            visibleText: Array(keyText),
            inferredState: inferredState
        )
    }

    private func findFocusedElementId() -> String? {
        for (id, element) in elementCache {
            if getBoolAttr(element, kAXFocusedAttribute) == true {
                return id
            }
        }
        return nil
    }

    private func getStringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func getBoolAttr(_ element: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}

// MARK: - Tool Definitions for LLM

let toolDefinitions = """
{
  "tools": [
    {
      "name": "observe_ui",
      "description": "Capture the current UI state of the app. Returns all visible elements with their IDs, roles, titles, values, and available actions. Call this first to see what's on screen, and after actions to see what changed.",
      "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
      "name": "diff_ui",
      "description": "Compare current UI to the last observation. Shows what elements were added, removed, or modified. Returns signals describing what changed semantically.",
      "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
      "name": "where_am_i",
      "description": "Get your current navigation context: location in UI hierarchy, known landmarks, recent actions, and current hypothesis about app state. Like VoiceOver's 'describe' command.",
      "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
      "name": "navigate",
      "description": "Move to adjacent element in the UI. Like pressing arrow keys in VoiceOver. Builds up mental model incrementally.",
      "input_schema": {
        "type": "object",
        "properties": {
          "direction": {"type": "string", "enum": ["next", "prev", "first", "last"], "description": "Direction to navigate"}
        },
        "required": ["direction"]
      }
    },
    {
      "name": "jump_to",
      "description": "Jump to next element of a specific type. Like VoiceOver rotor - jump between headings, buttons, text fields, etc.",
      "input_schema": {
        "type": "object",
        "properties": {
          "role": {"type": "string", "description": "Element role to find: Button, TextField, StaticText, Image, etc."},
          "direction": {"type": "string", "enum": ["next", "prev"], "default": "next"}
        },
        "required": ["role"]
      }
    },
    {
      "name": "list_landmarks",
      "description": "Find and list all landmarks/regions in the UI: toolbar, sidebar, main content, navigation, search, forms. Helps orient yourself.",
      "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
      "name": "go_to_landmark",
      "description": "Jump directly to a landmark by type or index number.",
      "input_schema": {
        "type": "object",
        "properties": {
          "identifier": {"type": "string", "description": "Landmark type (toolbar, sidebar, main) or index number from list_landmarks"}
        },
        "required": ["identifier"]
      }
    },
    {
      "name": "describe_current",
      "description": "Get detailed description of the currently focused element. Like VoiceOver's extended description.",
      "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
      "name": "list_nearby",
      "description": "List actionable elements near current position. Helps understand what actions are available without seeing everything.",
      "input_schema": {
        "type": "object",
        "properties": {
          "count": {"type": "integer", "default": 10, "description": "How many nearby elements to list"}
        },
        "required": []
      }
    },
    {
      "name": "set_hypothesis",
      "description": "Record your current belief about the app state. This helps maintain context across actions. Example: 'I am on the login screen and need to enter credentials'",
      "input_schema": {
        "type": "object",
        "properties": {
          "hypothesis": {"type": "string", "description": "Your current understanding of where you are and what state the app is in"}
        },
        "required": ["hypothesis"]
      }
    },
    {
      "name": "click",
      "description": "Click/press a UI element by its ID. Use for buttons, checkboxes, menu items, etc.",
      "input_schema": {
        "type": "object",
        "properties": {
          "element_id": {"type": "string", "description": "The element ID (e.g., 'e5')"}
        },
        "required": ["element_id"]
      }
    },
    {
      "name": "type",
      "description": "Type text into a text field or text area by element ID.",
      "input_schema": {
        "type": "object",
        "properties": {
          "element_id": {"type": "string", "description": "The text field element ID"},
          "text": {"type": "string", "description": "The text to type"}
        },
        "required": ["element_id", "text"]
      }
    },
    {
      "name": "focus",
      "description": "Set focus to a specific element.",
      "input_schema": {
        "type": "object",
        "properties": {
          "element_id": {"type": "string", "description": "The element ID to focus"}
        },
        "required": ["element_id"]
      }
    },
    {
      "name": "press_key",
      "description": "Press a keyboard key, optionally with modifiers. Use for Enter, Tab, Escape, keyboard shortcuts, etc.",
      "input_schema": {
        "type": "object",
        "properties": {
          "key": {"type": "string", "description": "Key name: return, tab, escape, space, delete, up, down, left, right, or a-z"},
          "modifiers": {"type": "array", "items": {"type": "string"}, "description": "Optional modifiers: cmd, shift, alt, ctrl"}
        },
        "required": ["key"]
      }
    },
    {
      "name": "wait",
      "description": "Wait for a specified time. Use after actions that trigger animations or loading.",
      "input_schema": {
        "type": "object",
        "properties": {
          "seconds": {"type": "number", "description": "Seconds to wait (e.g., 0.5, 1, 2)"}
        },
        "required": ["seconds"]
      }
    },
    {
      "name": "task_complete",
      "description": "Signal that the task has been completed successfully.",
      "input_schema": {
        "type": "object",
        "properties": {
          "summary": {"type": "string", "description": "Brief summary of what was accomplished"}
        },
        "required": ["summary"]
      }
    },
    {
      "name": "task_failed",
      "description": "Signal that the task cannot be completed.",
      "input_schema": {
        "type": "object",
        "properties": {
          "reason": {"type": "string", "description": "Why the task failed"}
        },
        "required": ["reason"]
      }
    }
  ]
}
"""

// MARK: - REPL Mode

func runREPL(agent: AppAgent) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]

    func printResult(_ result: ToolResult) {
        if let data = try? encoder.encode(result),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    print("AppAgent REPL - Connected to \(agent.appName)")
    print("Commands: observe, diff, click <id>, type <id> <text>, focus <id>, key <key> [mods], wait <secs>, tools, quit")
    print("")

    while true {
        print("> ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces), !line.isEmpty else { continue }

        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        let cmd = parts[0].lowercased()

        switch cmd {
        case "quit", "exit", "q":
            print("Bye!")
            return
        case "observe", "o":
            printResult(agent.observeUI())
        case "diff", "d":
            printResult(agent.diffUI())
        case "click", "c":
            guard parts.count >= 2 else { print("Usage: click <element_id>"); continue }
            printResult(agent.click(elementId: parts[1]))
        case "type", "t":
            guard parts.count >= 3 else { print("Usage: type <element_id> <text>"); continue }
            printResult(agent.type(elementId: parts[1], text: parts[2]))
        case "focus", "f":
            guard parts.count >= 2 else { print("Usage: focus <element_id>"); continue }
            printResult(agent.focus(elementId: parts[1]))
        case "key", "k":
            guard parts.count >= 2 else { print("Usage: key <keyname> [cmd,shift,...]"); continue }
            let mods = parts.count > 2 ? parts[2].split(separator: ",").map(String.init) : []
            printResult(agent.pressKey(key: parts[1], modifiers: mods))
        case "wait", "w":
            guard parts.count >= 2, let secs = Double(parts[1]) else { print("Usage: wait <seconds>"); continue }
            printResult(agent.wait(seconds: secs))
        case "tools":
            print(toolDefinitions)
        case "help", "h", "?":
            print("Commands:")
            print("  observe, o          - Capture current UI state")
            print("  diff, d             - Show changes since last observe")
            print("  click, c <id>       - Click element")
            print("  type, t <id> <text> - Type into element")
            print("  focus, f <id>       - Focus element")
            print("  key, k <key> [mods] - Press key (mods: cmd,shift,alt,ctrl)")
            print("  wait, w <secs>      - Wait")
            print("  tools               - Show LLM tool definitions")
            print("  quit, q             - Exit")
        default:
            print("Unknown command: \(cmd). Type 'help' for commands.")
        }
    }
}

// MARK: - JSON-RPC Mode (for LLM integration)

func runJSONRPC(agent: AppAgent) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    struct RPCRequest: Codable {
        let tool: String
        let params: [String: AnyCodable]?
    }

    while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(RPCRequest.self, from: data) else {
            print("{\"success\":false,\"message\":\"Invalid JSON\"}")
            continue
        }

        let result: ToolResult
        switch request.tool {
        // Core observation
        case "observe_ui":
            result = agent.observeUI()
        case "diff_ui":
            result = agent.diffUI()

        // VoiceOver-style navigation
        case "where_am_i":
            result = agent.whereAmI()
        case "navigate":
            let direction = (request.params?["direction"]?.value as? String) ?? "next"
            result = agent.navigate(direction: direction)
        case "jump_to":
            let role = (request.params?["role"]?.value as? String) ?? "Button"
            let direction = (request.params?["direction"]?.value as? String) ?? "next"
            result = agent.jumpTo(role: role, direction: direction)
        case "list_landmarks":
            result = agent.listLandmarks()
        case "go_to_landmark":
            let identifier = (request.params?["identifier"]?.value as? String) ?? ""
            result = agent.goToLandmark(identifier: identifier)
        case "describe_current":
            result = agent.describeCurrent()
        case "list_nearby":
            let count = (request.params?["count"]?.value as? Int) ?? 10
            result = agent.listNearby(count: count)
        case "find_content":
            let query = request.params?["query"]?.value as? String
            let count = (request.params?["count"]?.value as? Int) ?? 20
            result = agent.findContent(query: query, count: count)
        case "set_hypothesis":
            let hypothesis = (request.params?["hypothesis"]?.value as? String) ?? ""
            result = agent.setHypothesis(hypothesis)

        // Actions
        case "click":
            let elementId = (request.params?["element_id"]?.value as? String) ?? ""
            result = agent.click(elementId: elementId)
        case "type":
            let elementId = (request.params?["element_id"]?.value as? String) ?? ""
            let text = (request.params?["text"]?.value as? String) ?? ""
            result = agent.type(elementId: elementId, text: text)
        case "focus":
            let elementId = (request.params?["element_id"]?.value as? String) ?? ""
            result = agent.focus(elementId: elementId)
        case "press_key":
            let key = (request.params?["key"]?.value as? String) ?? ""
            let mods = (request.params?["modifiers"]?.value as? [String]) ?? []
            result = agent.pressKey(key: key, modifiers: mods)
        case "wait":
            let secs = (request.params?["seconds"]?.value as? Double) ?? 1.0
            result = agent.wait(seconds: secs)

        default:
            result = ToolResult(success: false, message: "Unknown tool: \(request.tool)", data: nil)
        }

        if let json = try? encoder.encode(result), let str = String(data: json, encoding: .utf8) {
            print(str)
            fflush(stdout)
        }
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("""
    Usage: swift AppAgent.swift <AppName> [options]

    Options:
      --repl          Interactive mode (default)
      --json-rpc      JSON-RPC mode for LLM integration (reads JSON from stdin)
      --tools         Print tool definitions for LLM and exit

    Examples:
      swift AppAgent.swift Safari --repl
      swift AppAgent.swift Safari --tools
      echo '{"tool":"observe_ui"}' | swift AppAgent.swift Safari --json-rpc
    """)
    exit(1)
}

// Check accessibility
let checkOpt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
guard AXIsProcessTrustedWithOptions([checkOpt: true] as CFDictionary) else {
    fputs("Error: Accessibility permission required\n", stderr)
    exit(1)
}

if args.contains("--tools") {
    print(toolDefinitions)
    exit(0)
}

let appName = args[1]
let agent = AppAgent(appName: appName)

let connectResult = agent.connect()
guard connectResult.success else {
    fputs("Error: \(connectResult.message)\n", stderr)
    fputs("Running apps:\n", stderr)
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        fputs("  - \(app.localizedName ?? "Unknown")\n", stderr)
    }
    exit(1)
}

if args.contains("--json-rpc") {
    runJSONRPC(agent: agent)
} else {
    runREPL(agent: agent)
}
