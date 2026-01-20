import Testing
import Foundation
@testable import AppAutomationCore

@Suite("Automation Core Tests")
struct AutomationCoreTests {
    
    @Test("AutomationSelector encoding/decoding")
    func testSelectorCodable() throws {
        let selector = AutomationSelector(
            role: SelectorField(value: "AXButton", match: .exact),
            title: SelectorField(value: "Submit", match: .contains),
            limit: 10,
            enabled: true
        )
        
        let data = try JSONEncoder().encode(selector)
        let decoded = try JSONDecoder().decode(AutomationSelector.self, from: data)
        
        #expect(decoded.role?.value == "AXButton")
        #expect(decoded.role?.match == .exact)
        #expect(decoded.title?.value == "Submit")
        #expect(decoded.title?.match == .contains)
        #expect(decoded.enabled == true)
        #expect(decoded.limit == 10)
    }
    
    @Test("AutomationAction encoding/decoding")
    func testActionCodable() throws {
        let action = AutomationAction(
            action: .click,
            selector: AutomationSelector(role: SelectorField(value: "AXButton")),
            params: ["text": AnyCodableValue("Hello")]
        )
        
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AutomationAction.self, from: data)
        
        #expect(decoded.action == .click)
        #expect(decoded.selector?.role?.value == "AXButton")
        #expect(decoded.params?["text"]?.value as? String == "Hello")
    }
    
    @Test("AutomationResponse encoding/decoding")
    func testResponseCodable() throws {
        let response = AutomationResponse<AnyCodableValue>(
            success: true,
            message: "Done",
            data: AnyCodableValue("result")
        )
        
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AutomationResponse<AnyCodableValue>.self, from: data)
        
        #expect(decoded.success == true)
        #expect(decoded.message == "Done")
        #expect(decoded.data?.value as? String == "result")
    }
    
    @Test("AutomationError codes")
    func testErrorCodes() throws {
        let response = AutomationResponse<AnyCodableValue>(
            success: false,
            errorCode: .elementNotFound,
            message: "No element"
        )
        
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AutomationResponse<AnyCodableValue>.self, from: data)
        
        #expect(decoded.success == false)
        #expect(decoded.errorCode == .elementNotFound)
    }
    
    @Test("AutomationSnapshot encoding")
    func testSnapshotCodable() throws {
        let element = AutomationElement(
            id: "e1",
            role: "AXButton",
            title: "OK",
            value: nil,
            enabled: true,
            focused: false,
            path: "AXWindow > AXButton",
            bounds: AutomationBounds(minX: 0, minY: 0, maxX: 100, maxY: 50),
            actions: ["AXPress"]
        )
        
        let snapshot = AutomationSnapshot(
            timestamp: "2026-01-20T00:00:00Z",
            appName: "TestApp",
            pid: 1234,
            focusedElement: nil,
            elements: [element],
            hash: "abc123"
        )
        
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AutomationSnapshot.self, from: data)
        
        #expect(decoded.appName == "TestApp")
        #expect(decoded.elements.count == 1)
        #expect(decoded.elements.first?.role == "AXButton")
    }
    
    @Test("AutomationDiff building")
    func testDiffBuilder() throws {
        let element1 = AutomationElement(
            id: "e1",
            role: "AXButton",
            title: "Submit",
            value: nil,
            enabled: true,
            focused: false,
            path: "AXWindow > AXButton",
            bounds: nil,
            actions: []
        )
        
        let element2 = AutomationElement(
            id: "e1",
            role: "AXButton",
            title: "Submit",
            value: "clicked",
            enabled: true,
            focused: true,
            path: "AXWindow > AXButton",
            bounds: nil,
            actions: []
        )
        
        let element3 = AutomationElement(
            id: "e2",
            role: "AXStaticText",
            title: "New",
            value: nil,
            enabled: true,
            focused: false,
            path: "AXWindow > AXStaticText",
            bounds: nil,
            actions: []
        )
        
        let prev = AutomationSnapshot(
            timestamp: "t1",
            appName: "App",
            pid: 1,
            focusedElement: nil,
            elements: [element1],
            hash: "h1"
        )
        
        let curr = AutomationSnapshot(
            timestamp: "t2",
            appName: "App",
            pid: 1,
            focusedElement: "e1",
            elements: [element2, element3],
            hash: "h2"
        )
        
        let diff = AutomationDiffBuilder.build(previous: prev, current: curr)
        
        #expect(diff.changed == true)
        #expect(diff.added.count >= 1)
        #expect(diff.modified.count >= 1)
    }
    
    @Test("JSONRPCEnvelope encoding")
    func testJSONRPCEnvelope() throws {
        let envelope = JSONRPCEnvelope(
            id: "1",
            method: "observe",
            params: ["app": AnyCodableValue("Safari")]
        )
        
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(JSONRPCEnvelope.self, from: data)
        
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == "1")
        #expect(decoded.method == "observe")
        #expect(decoded.params?["app"]?.value as? String == "Safari")
    }
    
    @Test("StreamToken encoding")
    func testStreamToken() throws {
        let token = AutomationStreamToken(value: "stream-123")
        
        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(AutomationStreamToken.self, from: data)
        
        #expect(decoded.value == "stream-123")
    }
    
    @Test("CapabilityProfile encoding")
    func testCapabilityProfile() throws {
        let profile = CapabilityProfile(
            appName: "Safari",
            pid: 1234,
            axScore: 0.8,
            supportsScriptingBridge: true,
            supportsAppleScript: true,
            supportsUrlSchemes: true,
            lastUpdated: "2026-01-20"
        )
        
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CapabilityProfile.self, from: data)
        
        #expect(decoded.appName == "Safari")
        #expect(decoded.axScore == 0.8)
        #expect(decoded.supportsScriptingBridge == true)
    }
}
