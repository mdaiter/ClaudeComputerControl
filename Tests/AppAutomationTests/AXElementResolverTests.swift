import Testing
import Foundation
@testable import AppAutomationCore
@testable import AppAutomationAX

@Suite("AX Element Resolver Tests")
struct AXElementResolverTests {
    
    let resolver = AXElementResolver()
    
    func makeElement(
        id: String = "e1",
        role: String = "AXButton",
        title: String? = nil,
        value: String? = nil,
        enabled: Bool = true,
        focused: Bool = false,
        path: String = "AXWindow > AXButton"
    ) -> AutomationElement {
        AutomationElement(
            id: id,
            role: role,
            title: title,
            value: value,
            enabled: enabled,
            focused: focused,
            path: path,
            bounds: nil,
            actions: []
        )
    }
    
    @Test("Matches exact role")
    func testExactRoleMatch() {
        let element = makeElement(role: "AXButton")
        let selector = AutomationSelector(role: SelectorField(value: "AXButton", match: .exact))
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
    
    @Test("Does not match wrong role")
    func testRoleMismatch() {
        let element = makeElement(role: "AXButton")
        let selector = AutomationSelector(role: SelectorField(value: "AXTextField", match: .exact))
        
        #expect(resolver.matches(element, selector: selector) == false)
    }
    
    @Test("Matches contains title")
    func testContainsTitle() {
        let element = makeElement(title: "Submit Form")
        let selector = AutomationSelector(title: SelectorField(value: "Submit", match: .contains))
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
    
    @Test("Matches enabled filter")
    func testEnabledFilter() {
        let element = makeElement(enabled: true)
        let selectorEnabled = AutomationSelector(enabled: true)
        let selectorDisabled = AutomationSelector(enabled: false)
        
        #expect(resolver.matches(element, selector: selectorEnabled) == true)
        #expect(resolver.matches(element, selector: selectorDisabled) == false)
    }
    
    @Test("Matches focused filter")
    func testFocusedFilter() {
        let element = makeElement(focused: true)
        let selectorFocused = AutomationSelector(focused: true)
        let selectorUnfocused = AutomationSelector(focused: false)
        
        #expect(resolver.matches(element, selector: selectorFocused) == true)
        #expect(resolver.matches(element, selector: selectorUnfocused) == false)
    }
    
    @Test("Matches path contains")
    func testPathContains() {
        let element = makeElement(path: "AXApplication > AXWindow > AXButton")
        let selector = AutomationSelector(path: SelectorField(value: "AXWindow", match: .contains))
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
    
    @Test("Matches multiple criteria")
    func testMultipleCriteria() {
        let element = makeElement(
            role: "AXButton",
            title: "Submit Form",
            enabled: true
        )
        
        let selector = AutomationSelector(
            role: SelectorField(value: "AXButton", match: .exact),
            title: SelectorField(value: "Submit", match: .contains),
            enabled: true
        )
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
    
    @Test("Fails when one criterion fails")
    func testPartialMismatch() {
        let element = makeElement(
            role: "AXButton",
            title: "Cancel",
            enabled: true
        )
        
        let selector = AutomationSelector(
            role: SelectorField(value: "AXButton", match: .exact),
            title: SelectorField(value: "Submit", match: .contains),
            enabled: true
        )
        
        #expect(resolver.matches(element, selector: selector) == false)
    }
    
    @Test("Empty selector matches all")
    func testEmptySelector() {
        let element = makeElement()
        let selector = AutomationSelector()
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
    
    @Test("Case insensitive contains match")
    func testCaseInsensitive() {
        let element = makeElement(title: "SUBMIT BUTTON")
        let selector = AutomationSelector(title: SelectorField(value: "submit", match: .contains))
        
        #expect(resolver.matches(element, selector: selector) == true)
    }
}
