import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Support) import SwiftInterface
import SwiftDump
import Demangling

/// Analyzes Swift interfaces and extracts API entries with certainty scores.
public struct APICertaintyAnalyzer<MachO: MachOSwiftSectionRepresentableWithCache & Sendable> {
    private let machO: MachO
    private let builder: SwiftInterfaceBuilder<MachO>

    public init(machO: MachO, builder: SwiftInterfaceBuilder<MachO>) {
        self.machO = machO
        self.builder = builder
    }

    /// Analyzes the indexed interface and produces an API catalog.
    @_spi(Support)
    public func analyze(binaryPath: String) async throws -> APICatalog {
        let indexer = builder.indexer

        var types: [APIEntry] = []
        var protocols: [APIEntry] = []
        var globalFunctions: [APIEntry] = []
        var globalVariables: [APIEntry] = []

        // Process root type definitions
        for (_, typeDefinition) in indexer.rootTypeDefinitions {
            if let entry = try await analyzeType(typeDefinition) {
                types.append(entry)
            }
        }

        // Process root protocol definitions
        for (_, protocolDefinition) in indexer.rootProtocolDefinitions {
            if let entry = try await analyzeProtocol(protocolDefinition) {
                protocols.append(entry)
            }
        }

        // Process global functions
        for functionDefinition in indexer.globalFunctionDefinitions {
            if let entry = analyzeFunction(functionDefinition, parentType: nil) {
                globalFunctions.append(entry)
            }
        }

        // Process global variables
        for variableDefinition in indexer.globalVariableDefinitions {
            if let entry = analyzeVariable(variableDefinition, parentType: nil) {
                globalVariables.append(entry)
            }
        }

        return APICatalog(
            binaryPath: binaryPath,
            types: types,
            protocols: protocols,
            globalFunctions: globalFunctions,
            globalVariables: globalVariables
        )
    }

    // MARK: - Type Analysis

    private func analyzeType(_ typeDefinition: TypeDefinition) async throws -> APIEntry? {
        let typeName = typeDefinition.typeName
        let name = typeName.name
        let currentName = typeName.currentName

        let kind: APIKind = switch typeName.kind {
        case .enum: .enum
        case .struct: .struct
        case .class: .class
        }

        // Compute type-level certainty (types themselves are generally easy to reference)
        let factors = ComplexityFactors(
            parameterCount: 0,
            hasAsync: false,
            hasThrows: false,
            hasClosures: false,
            nestingDepth: computeNestingDepth(name),
            genericParams: countGenericParams(typeName.node)
        )
        let certainty = CertaintyScore.compute(from: factors)

        // Build signature
        let signature = "\(kind.displayName) \(currentName)"

        // Analyze children
        var children: [APIEntry] = []

        // Allocators (initializers)
        for allocator in typeDefinition.allocators {
            if let entry = analyzeFunction(allocator, parentType: name, kind: .initializer) {
                children.append(entry)
            }
        }

        // Instance functions
        for function in typeDefinition.functions {
            if let entry = analyzeFunction(function, parentType: name) {
                children.append(entry)
            }
        }

        // Static functions
        for function in typeDefinition.staticFunctions {
            if let entry = analyzeFunction(function, parentType: name, isStatic: true) {
                children.append(entry)
            }
        }

        // Instance variables
        for variable in typeDefinition.variables {
            if let entry = analyzeVariable(variable, parentType: name) {
                children.append(entry)
            }
        }

        // Static variables
        for variable in typeDefinition.staticVariables {
            if let entry = analyzeVariable(variable, parentType: name, isStatic: true) {
                children.append(entry)
            }
        }

        // Nested types
        for childType in typeDefinition.typeChildren {
            if let entry = try await analyzeType(childType) {
                children.append(entry)
            }
        }

        // Nested protocols
        for childProtocol in typeDefinition.protocolChildren {
            if let entry = try await analyzeProtocol(childProtocol) {
                children.append(entry)
            }
        }

        // Sort children by certainty
        children = APIEntry.sortedByCertainty(children)

        return APIEntry(
            id: name,
            kind: kind,
            name: currentName,
            signature: signature,
            certainty: certainty,
            parentType: typeDefinition.parent?.typeName.name,
            offset: nil,
            children: children
        )
    }

    // MARK: - Protocol Analysis

    private func analyzeProtocol(_ protocolDefinition: ProtocolDefinition) async throws -> APIEntry? {
        let protocolName = protocolDefinition.protocolName
        let name = protocolName.name
        let currentName = protocolName.currentName

        // Protocols are reference types but can have complex requirements
        let factors = ComplexityFactors(
            parameterCount: 0,
            hasAsync: false,
            hasThrows: false,
            hasClosures: false,
            nestingDepth: computeNestingDepth(name),
            genericParams: 0,
            hasProtocolParams: !protocolDefinition.associatedTypes.isEmpty
        )
        let certainty = CertaintyScore.compute(from: factors)

        let signature = "protocol \(currentName)"

        var children: [APIEntry] = []

        // Protocol requirements (functions)
        for function in protocolDefinition.functions {
            if let entry = analyzeFunction(function, parentType: name) {
                children.append(entry)
            }
        }

        // Protocol requirements (variables)
        for variable in protocolDefinition.variables {
            if let entry = analyzeVariable(variable, parentType: name) {
                children.append(entry)
            }
        }

        children = APIEntry.sortedByCertainty(children)

        return APIEntry(
            id: name,
            kind: .protocol,
            name: currentName,
            signature: signature,
            certainty: certainty,
            parentType: protocolDefinition.parent?.typeName.name,
            offset: nil,
            children: children
        )
    }

    // MARK: - Function Analysis

    private func analyzeFunction(
        _ function: FunctionDefinition,
        parentType: String?,
        kind: APIKind = .function,
        isStatic: Bool = false
    ) -> APIEntry? {
        let node = function.node
        let name = function.name
        let signature = node.print(using: .interfaceBuilderOnly)

        let factors = analyzeNodeComplexity(node)
        let certainty = CertaintyScore.compute(from: factors)

        let id = parentType.map { "\($0).\(name)" } ?? name

        return APIEntry(
            id: id,
            kind: kind,
            name: name,
            signature: signature,
            certainty: certainty,
            parentType: parentType,
            offset: function.offset.map { "0x\(String($0, radix: 16))" },
            isStatic: isStatic,
            isOverride: function.isOverride
        )
    }

    // MARK: - Variable Analysis

    private func analyzeVariable(
        _ variable: VariableDefinition,
        parentType: String?,
        isStatic: Bool = false
    ) -> APIEntry? {
        let node = variable.node
        let name = variable.name
        let signature = node.print(using: .interfaceBuilderOnly)

        let factors = analyzeNodeComplexity(node)
        let certainty = CertaintyScore.compute(from: factors)

        let id = parentType.map { "\($0).\(name)" } ?? name

        return APIEntry(
            id: id,
            kind: .property,
            name: name,
            signature: signature,
            certainty: certainty,
            parentType: parentType,
            offset: variable.offset.map { "0x\(String($0, radix: 16))" },
            isStatic: isStatic,
            isOverride: variable.isOverride
        )
    }

    // MARK: - Complexity Analysis Helpers

    private func analyzeNodeComplexity(_ node: Node) -> ComplexityFactors {
        var factors = ComplexityFactors()

        // Count parameters
        factors.parameterCount = countParameters(node)

        // Check for async
        factors.hasAsync = node.contains(.asyncAnnotation)

        // Check for throws
        factors.hasThrows = node.contains(.throwsAnnotation)

        // Check for closures in parameters or return type
        factors.hasClosures = containsClosures(node)

        // Count generic parameters
        factors.genericParams = countGenericParams(node)

        // Check for complex return types
        factors.hasComplexReturnType = hasComplexReturnType(node)

        // Check for protocol/existential types in parameters
        factors.hasProtocolParams = containsProtocolTypes(node)

        return factors
    }

    private func countParameters(_ node: Node) -> Int {
        // Look for ArgumentTuple or LabelList
        if let argumentTuple = node.first(of: .argumentTuple) {
            return argumentTuple.children.count
        }
        if let labelList = node.first(of: .labelList) {
            return labelList.children.count
        }
        return 0
    }

    private func containsClosures(_ node: Node) -> Bool {
        for child in node.preorder() {
            if child.kind == .functionType || child.kind == .noEscapeFunctionType {
                return true
            }
        }
        return false
    }

    private func countGenericParams(_ node: Node) -> Int {
        var count = 0
        for child in node.preorder() {
            if child.kind == .dependentGenericParamType {
                count += 1
            }
        }
        return count
    }

    private func hasComplexReturnType(_ node: Node) -> Bool {
        // Look for async streams, Result types, complex generics in return
        if let returnType = node.first(of: .returnType) {
            for child in returnType.preorder() {
                if child.kind == .boundGenericStructure ||
                   child.kind == .boundGenericClass ||
                   child.kind == .boundGenericEnum {
                    // Check if it's an async stream or similar
                    if let text = child.children.first?.text,
                       text.contains("AsyncStream") || text.contains("AsyncThrowingStream") {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func containsProtocolTypes(_ node: Node) -> Bool {
        for child in node.preorder() {
            if child.kind == .protocolList ||
               child.kind == .protocol {
                return true
            }
        }
        return false
    }

    private func computeNestingDepth(_ name: String) -> Int {
        // Count dots in the name to determine nesting depth
        return name.components(separatedBy: ".").count
    }
}
