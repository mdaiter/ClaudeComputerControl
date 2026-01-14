import Foundation

/// The kind of API entry
public enum APIKind: String, Codable, Sendable, CaseIterable {
    case function
    case property
    case initializer
    case subscriptEntry = "subscript"
    case type
    case `protocol`
    case `enum`
    case `struct`
    case `class`

    public var displayName: String {
        switch self {
        case .function: return "func"
        case .property: return "var"
        case .initializer: return "init"
        case .subscriptEntry: return "subscript"
        case .type: return "type"
        case .protocol: return "protocol"
        case .enum: return "enum"
        case .struct: return "struct"
        case .class: return "class"
        }
    }
}

/// Represents a single API entry extracted from a binary.
public struct APIEntry: Codable, Sendable, Identifiable, Hashable {
    /// Unique identifier for this API (fully qualified name)
    public let id: String

    /// The kind of API (function, property, initializer, etc.)
    public let kind: APIKind

    /// The display name (short form)
    public let name: String

    /// The full signature as it would appear in Swift code
    public let signature: String

    /// The certainty score for this API
    public let certainty: CertaintyScore

    /// The parent type name (if this is a member)
    public let parentType: String?

    /// The module this API belongs to
    public let module: String?

    /// Binary offset (if available)
    public let offset: String?

    /// Whether this is a static/class member
    public let isStatic: Bool

    /// Whether this is an override
    public let isOverride: Bool

    /// Child APIs (for types with members)
    public var children: [APIEntry]

    public init(
        id: String,
        kind: APIKind,
        name: String,
        signature: String,
        certainty: CertaintyScore,
        parentType: String? = nil,
        module: String? = nil,
        offset: String? = nil,
        isStatic: Bool = false,
        isOverride: Bool = false,
        children: [APIEntry] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.signature = signature
        self.certainty = certainty
        self.parentType = parentType
        self.module = module
        self.offset = offset
        self.isStatic = isStatic
        self.isOverride = isOverride
        self.children = children
    }

    /// A display string for list views: "[score] name"
    public var listDisplayString: String {
        "[\(String(format: "%2d", certainty.score))] \(name)"
    }

    /// A short description for quick reference
    public var shortDescription: String {
        if let parent = parentType {
            return "\(parent).\(name)"
        }
        return name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: APIEntry, rhs: APIEntry) -> Bool {
        lhs.id == rhs.id
    }
}

extension APIEntry {
    /// Returns all APIs flattened (including children)
    public var flattened: [APIEntry] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.flattened)
        }
        return result
    }

    /// Returns APIs sorted by certainty (highest first)
    public static func sortedByCertainty(_ apis: [APIEntry]) -> [APIEntry] {
        apis.sorted { $0.certainty.score > $1.certainty.score }
    }

    /// Filter APIs by minimum certainty score
    public static func filtered(_ apis: [APIEntry], minCertainty: Int) -> [APIEntry] {
        apis.filter { $0.certainty.score >= minCertainty }
    }

    /// Search APIs by name
    public static func search(_ apis: [APIEntry], query: String) -> [APIEntry] {
        guard !query.isEmpty else { return apis }
        let lowercasedQuery = query.lowercased()
        return apis.filter {
            $0.name.lowercased().contains(lowercasedQuery) ||
            $0.signature.lowercased().contains(lowercasedQuery) ||
            $0.id.lowercased().contains(lowercasedQuery)
        }
    }
}
