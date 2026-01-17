#if os(macOS)

import Foundation
import TypeIndexing

@available(macOS 13.0, *)
public enum SwiftInterfaceCatalogImporter {
    public static func load(from path: String) async throws -> APICatalog {
        let moduleName = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let interfaceFile = SwiftInterfaceGeneratedFile(moduleName: moduleName, contents: contents)
        let parser = SwiftInterfaceParser(file: interfaceFile)
        try await parser.index()

        let typeInfos = await parser.typeInfos

        var typeEntries: [APIEntry] = []
        var protocolEntries: [APIEntry] = []

        for typeInfo in typeInfos {
            guard let entry = makeTypeEntry(typeInfo, moduleName: moduleName) else { continue }
            switch entry.kind {
            case .protocol:
                protocolEntries.append(entry)
            case .enum, .struct, .class:
                typeEntries.append(entry)
            default:
                typeEntries.append(entry)
            }
        }

        return APICatalog(
            binaryPath: path,
            types: typeEntries,
            protocols: protocolEntries,
            globalFunctions: [],
            globalVariables: []
        )
    }

    private static func makeTypeEntry(
        _ typeInfo: SwiftInterfaceParser.TypeInfo,
        moduleName: String
    ) -> APIEntry? {
        guard let kind = mapTypeKind(typeInfo.kind) else { return nil }
        let simpleName = typeInfo.name.split(separator: ".").last.map(String.init) ?? typeInfo.name
        var signature = "\(kind.displayName) \(typeInfo.name)"
        if !typeInfo.genericParams.isEmpty {
            signature += "<\(typeInfo.genericParams.joined(separator: ", "))>"
        }
        let children = typeInfo.members.compactMap {
            makeMemberEntry($0, parentName: typeInfo.name, moduleName: moduleName)
        }
        let nestingDepth = max(1, typeInfo.name.split(separator: ".").count)
        let factors = ComplexityFactors(
            parameterCount: 0,
            nestingDepth: nestingDepth,
            genericParams: typeInfo.genericParams.count
        )
        return APIEntry(
            id: "\(moduleName).\(typeInfo.name)",
            kind: kind,
            name: simpleName,
            signature: signature,
            certainty: CertaintyScore.compute(from: factors),
            parentType: nil,
            module: moduleName,
            offset: nil,
            isStatic: false,
            isOverride: false,
            children: children
        )
    }

    private static func makeMemberEntry(
        _ member: SwiftInterfaceParser.MemberInfo,
        parentName: String,
        moduleName: String
    ) -> APIEntry? {
        guard let kind = mapMemberKind(member.kind) else { return nil }
        let factors = ComplexityFactors(parameterCount: 0)
        return APIEntry(
            id: "\(moduleName).\(parentName).\(member.name)",
            kind: kind,
            name: member.name,
            signature: member.name,
            certainty: CertaintyScore.compute(from: factors),
            parentType: parentName,
            module: moduleName,
            offset: nil,
            isStatic: false,
            isOverride: false,
            children: []
        )
    }

    private static func mapTypeKind(_ kind: SwiftInterfaceParser.TypeKind) -> APIKind? {
        switch kind {
        case .struct: return .struct
        case .class: return .class
        case .enum: return .enum
        case .protocol: return .protocol
        }
    }

    private static func mapMemberKind(_ kind: SwiftInterfaceParser.MemberKind) -> APIKind? {
        switch kind {
        case .property: return .property
        case .method: return .function
        case .initializer: return .initializer
        case .subscript: return .subscriptEntry
        case .associatedType: return .type
        case .enumCase: return .function
        }
    }
}

#endif
